const functions = require("firebase-functions");
const admin     = require("firebase-admin");
// Use global fetch provided by Node 18+ runtime

// 1) Firebase Admin SDK 초기화
admin.initializeApp();

// 3) HTTP onRequest Function: getCredits
// Returns current credits (defaults to 1000 if no record)
exports.getCredits = functions.https.onRequest(async (req, res) => {
  try {
    // Authorization required
    const authHeader = req.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const idToken = authHeader.split('Bearer ')[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;
    // Fetch or initialize
    const userRef = admin.firestore().collection('users').doc(uid);
    const doc = await userRef.get();
    const credits = doc.exists && typeof doc.data().credits === 'number'
      ? doc.data().credits
      : null;
    return res.json({ credits });
  } catch (err) {
    console.error('getCredits error:', err);
    return res.status(500).json({ error: err.message });
  }
});

// 4) HTTP onRequest Function: deductCredits
// Expects JSON { cost: number }, returns updated credits or error
exports.deductCredits = functions.https.onRequest(async (req, res) => {
  try {
    // Authorization required
    const authHeader = req.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const idToken = authHeader.split('Bearer ')[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;

    // Validate cost
    const { cost } = req.body;
    if (typeof cost !== 'number' || cost <= 0) {
      return res.status(400).json({ error: 'Bad Request: cost must be a positive number' });
    }

    // Transaction: deduct
    const userRef = admin.firestore().collection('users').doc(uid);
    const newCredits = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists || typeof snap.data().credits !== 'number') {
        throw new Error('No credits found for user');
      }
      const current = snap.data().credits;
      if (current < cost) {
        throw new Error('Insufficient credits');
      }
      const updated = current - cost;
      tx.set(userRef, { credits: updated }, { merge: true });
      return updated;
    });
    return res.json({ credits: newCredits });
  } catch (err) {
    console.error('deductCredits error:', err);
    if (err.message === 'Insufficient credits') {
      return res.status(429).json({ error: 'Insufficient credits' });
    }
    return res.status(500).json({ error: err.message });
  }
});

// Proxy function to forward chat requests to OpenAI without exposing API key
exports.chatProxy = functions.https.onRequest(async (req, res) => {
  console.log("chatProxy invocation start");
  console.log("ENV:", process.env);
  console.log("Request body:", JSON.stringify(req.body));
  try {
    // 1) Extract and verify Firebase ID token from Authorization header
    const authHeader = req.get?.("Authorization") || req.headers?.authorization || "";
    console.log("Incoming Firebase ID token:", authHeader);
    if (!authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Unauthorized: No token provided" });
    }
    const idToken = authHeader.split("Bearer ")[1].trim();
    try {
      await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      console.error("Token verification failed:", err);
      return res.status(401).json({ error: "Unauthorized: Invalid token" });
    }

    // 2) Extract messages from body
    const { messages } = req.body;
    if (!Array.isArray(messages)) {
      return res.status(400).json({ error: "Bad Request: messages must be an array" });
    }

    // 3) Fetch OpenAI API key from environment and debug
    const rawKey = process.env.OPENAI_API_KEY ?? "";
    console.log("Debug: OPENAI_API_KEY present:", !!rawKey);
    console.log("Debug: OPENAI_API_KEY first 5 chars:", rawKey ? rawKey.substring(0,5) + "..." : "<none>");
    if (!rawKey) {
      console.error("Missing OpenAI key in environment!");
      return res.status(500).json({ error: "Server misconfiguration: missing OpenAI key" });
    }

    // 4) Call OpenAI API with enhanced error logging
    let openaiResp;
    try {
      openaiResp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${rawKey}`,
          "Content-Type":  "application/json"
        },
        body: JSON.stringify({
          model: "gpt-4.1-nano",
          messages,
          temperature: 0.3,
          max_tokens:  32768
        })
      });
    } catch (networkErr) {
      console.error("Network error calling OpenAI API:", networkErr);
      return res.status(500).json({ error: "Network error contacting OpenAI" });
    }
    console.log(`OpenAI response status: ${openaiResp.status}`);
    if (!openaiResp.ok) {
      const text = await openaiResp.text();
      console.error(`OpenAI API error (status ${openaiResp.status}):`, text);
      return res.status(500).json({ error: `OpenAI API error: ${text}` });
    }
    const data = await openaiResp.json();

    // 5) Extract content, usage, and compute cost
    const content = data.choices?.[0]?.message?.content || "";
    const usage = data.usage || {};
    const promptTokens = usage.prompt_tokens || 0;
    const completionTokens = usage.completion_tokens || 0;
    const totalTokens = usage.total_tokens || (promptTokens + completionTokens);
    // Example cost rate: $0.002 per 1K tokens
    const costPerThousand = 0.002;
    const cost = ((promptTokens + completionTokens) / 1000) * costPerThousand;

    return res.json({
      content,
      usage: {
        prompt_tokens: promptTokens,
        completion_tokens: completionTokens,
        total_tokens: totalTokens
      },
      cost
    });
  } catch (e) {
    console.error("chatProxy error:", e, e.stack);
    return res.status(500).json({ error: e.message });
  }
});

// HTTP Function: logLogin
// Records lastLogin timestamp and optionally email for authenticated user, and sets createdAt/credits for new users
exports.logLogin = functions.https.onRequest(async (req, res) => {
  const idToken = req.headers.authorization?.split('Bearer ')[1];
  if (!idToken) return res.status(401).send('Unauthorized');

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const email = req.body.email || null;

    const userRef = admin.firestore().collection('users').doc(uid);
    const existing = await userRef.get();
    if (!existing.exists) {
      await userRef.set({
        email,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        credits: 1000,
        lastLogin: admin.firestore.FieldValue.serverTimestamp(),
        available: true
      });
    } else {
      await userRef.set({
        ...(email ? { email } : {}),
        lastLogin: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    }

    return res.status(200).send({ status: 'success' });
  } catch (err) {
    console.error("logLogin failed:", err);
    return res.status(500).send('Internal Server Error');
  }
});

// HTTP Function: logAction
// Records user actions like transcribe, summarize, export
exports.logAction = functions.https.onRequest(async (req, res) => {
  const idToken = req.headers.authorization?.split('Bearer ')[1];
  if (!idToken) return res.status(401).send('Unauthorized');

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const action = req.body;

    if (!action || !action.actionId || !action.type) {
      return res.status(400).send('Missing required action fields.');
    }

    const transcribe = action.transcribeMeta || {};
    const summarize = action.summarizeMeta || {};
    const exportData = action.exportMeta || {};

    const logDoc = {
      actionId: action.actionId,
      type: action.type,
      userId: uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: typeof action.success === "boolean" ? action.success : true,
      creditCost: action.creditCost || null,
      remainingCredits: action.remainingCredits || null,
      processingTime: action.processingTime || null,
      ...(action.type === 'transcribe' ? { transcribeMeta: transcribe } : {}),
      ...(action.type === 'summarize' ? { summarizeMeta: summarize } : {}),
      ...(action.type === 'export' ? { exportMeta: exportData } : {})
    };

    await admin.firestore().collection("actions").doc(action.actionId).set(logDoc);

    return res.status(200).send({ status: 'logged' });
  } catch (err) {
    console.error("logAction failed:", err);
    return res.status(500).send('Failed to log action');
  }
});

// HTTP Function: getUpdateInfo
// Returns version info and download URL for the given platform (mac/win)
exports.getUpdateInfo = functions.https.onRequest(async (req, res) => {
  try {
    const platform = (req.query.platform || 'mac').toLowerCase();
    const doc = await admin.firestore().collection("updates").doc("latest").get();
    if (!doc.exists) return res.status(404).send("Update info not found");

    const data = doc.data();
    const versionKey = platform === "win" ? "version_win" : "version_mac";
    const urlKey = platform === "win" ? "url_win" : "url_mac";
    const patchUrlKey = platform === "win" ? "patch_url_win" : "patch_url_mac";
    const patchFromKey = platform === "win" ? "patch_from_win" : "patch_from_mac";

    return res.status(200).json({
      version: data[versionKey],
      url: data[urlKey],
      patch_url: data[patchUrlKey],
      patch_from: data[patchFromKey]
    });
  } catch (err) {
    console.error("getUpdateInfo error:", err);
    return res.status(500).json({ error: "Failed to retrieve update info" });
  }
});
// HTTP Function: checkEmailVerified
// Returns { emailVerified: true/false } for authenticated user
exports.checkEmailVerified = functions.https.onRequest(async (req, res) => {
  const idToken = req.headers.authorization?.split('Bearer ')[1];
  if (!idToken) return res.status(401).send('Unauthorized');

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;
    const userRecord = await admin.auth().getUser(uid);
    return res.status(200).json({ email_verified: userRecord.emailVerified });
  } catch (err) {
    console.error("checkEmailVerified failed:", err);
    return res.status(500).send('Failed to check verification');
  }
});