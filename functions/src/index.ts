import {onCall, onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

// Firebase Admin 초기화
admin.initializeApp();

// OpenAI API 키 (환경변수에서 가져오기)
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

/**
 * chatProxy Function - OpenAI API 프록시
 */
export const chatProxy = onRequest(async (req, res) => {
  logger.info("chatProxy invocation start");

  try {
    // 1) Extract and verify Firebase ID token from Authorization header
    const authHeader = req.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized: No token provided"});
      return;
    }
    const idToken = authHeader.split("Bearer ")[1].trim();
    try {
      await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      logger.error("Token verification failed:", err);
      res.status(401).json({error: "Unauthorized: Invalid token"});
      return;
    }

    // 2) Extract messages from body
    const {messages} = req.body;
    if (!Array.isArray(messages)) {
      res.status(400).json({
        error: "Bad Request: messages must be an array",
      });
      return;
    }

    // 3) Fetch OpenAI API key from environment
    if (!OPENAI_API_KEY) {
      logger.error("Missing OpenAI key in environment!");
      res.status(500).json({
        error: "Server misconfiguration: missing OpenAI key",
      });
      return;
    }

    // 4) Call OpenAI API
    let openaiResp;
    try {
      openaiResp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages,
          temperature: 0.3,
          max_tokens: 16384,
        }),
      });
    } catch (networkErr) {
      logger.error("Network error calling OpenAI API:", networkErr);
      res.status(500).json({error: "Network error contacting OpenAI"});
      return;
    }

    if (!openaiResp.ok) {
      const text = await openaiResp.text();
      logger.error(`OpenAI API error (status ${openaiResp.status}):`, text);
      res.status(500).json({error: `OpenAI API error: ${text}`});
      return;
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

    res.json({
      content,
      usage: {
        prompt_tokens: promptTokens,
        completion_tokens: completionTokens,
        total_tokens: totalTokens,
      },
      cost,
    });
  } catch (e) {
    logger.error("chatProxy error:", e);
    res.status(500).json({error: (e as Error).message});
  }
});

interface ChunkOverviewRequest {
  segments: Array<{
    id: number;
    startSec: number;
    endSec: number;
    text: string;
  }>;
  chunkIndex: number;
  totalChunks: number;
}

interface ChunkOverviewResponse {
  chunk_index: number;
  main_topic: string;
  key_points: string[];
  structure: {
    start: string;
    development: string;
    end: string;
  };
  connection: {
    previous: string;
    next: string;
  };
  important_segments: number[];
}

/**
 * 청크별 개요 파악을 위한 Firebase Function
 */
export const getChunkOverview = onCall(async (request) => {
  try {
    logger.info("getChunkOverview 호출됨", {structuredData: true});

    if (!OPENAI_API_KEY) {
      throw new Error("OpenAI API 키가 설정되지 않았습니다.");
    }

    const data = request.data as ChunkOverviewRequest;
    const {segments, chunkIndex, totalChunks} = data;

    if (!segments || segments.length === 0) {
      throw new Error("세그먼트 데이터가 없습니다.");
    }

    // OpenAI API 호출
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `당신은 비디오 콘텐츠 분석 전문가입니다. 주어진 세그먼트들을 분석하여 구조화된 개요를 제공해주세요.

응답은 반드시 다음 JSON 형식으로만 제공해주세요:
{
  "chunk_index": ${chunkIndex},
  "main_topic": "주요 주제",
  "key_points": ["핵심 포인트 1", "핵심 포인트 2", "핵심 포인트 3"],
  "structure": {
    "start": "시작 부분 설명",
    "development": "전개 부분 설명", 
    "end": "마무리 부분 설명"
  },
  "connection": {
    "previous": "이전 청크와의 연결점",
    "next": "다음 청크와의 연결점"
  },
  "important_segments": [중요한 세그먼트 ID들]
}`,
          },
          {
            role: "user",
            content: `다음은 비디오의 ${chunkIndex}/${totalChunks} 청크 세그먼트들입니다:

${segments.map((s) =>
    `[${s.id}] ${s.startSec}s-${s.endSec}s: ${s.text}`
  ).join("\n")}

위 세그먼트들을 분석하여 JSON 형식으로 개요를 제공해주세요.`,
          },
        ],
        max_tokens: 32768,
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error("OpenAI API 호출 실패", {
        status: response.status,
        statusText: response.statusText,
        error: errorText,
      });
      throw new Error(`OpenAI API 호출 실패: ${response.status}`);
    }

    const result = await response.json();
    const content = result.choices[0].message.content;

    try {
      const overview = JSON.parse(content) as ChunkOverviewResponse;
      logger.info("청크 개요 생성 성공", {chunkIndex, totalChunks});
      return overview;
    } catch (parseError) {
      logger.error("JSON 파싱 실패", {content, error: parseError});
      // 파싱 실패 시 기본값 반환
      return {
        chunk_index: chunkIndex,
        main_topic: `청크 ${chunkIndex}`,
        key_points: ["내용 분석 실패"],
        structure: {start: "", development: "", end: ""},
        connection: {previous: "", next: ""},
        important_segments: [],
      };
    }
  } catch (error) {
    logger.error("getChunkOverview 오류", {error: (error as Error).message});
    throw new Error(`청크 개요 파악 실패: ${(error as Error).message}`);
  }
});

/**
 * 전체 구조 통합을 위한 Firebase Function
 */
export const integrateChunkOverviews = onCall(async (request) => {
  try {
    logger.info("integrateChunkOverviews 호출됨", {structuredData: true});

    if (!OPENAI_API_KEY) {
      throw new Error("OpenAI API 키가 설정되지 않았습니다.");
    }

    const {chunkOverviews} = request.data;

    if (!chunkOverviews || chunkOverviews.length === 0) {
      throw new Error("청크 개요 데이터가 없습니다.");
    }

    // OpenAI API 호출
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `당신은 비디오 콘텐츠 구조 분석 전문가입니다. 
여러 청크의 개요를 통합하여 전체적인 구조를 파악해주세요.

응답은 반드시 다음 JSON 형식으로만 제공해주세요:
{
  "overall_structure": "전체 구조 설명",
  "main_themes": ["주요 테마 1", "주요 테마 2", "주요 테마 3"],
  "flow_analysis": "흐름 분석",
  "key_transitions": ["전환점 1", "전환점 2"]
}`,
          },
          {
            role: "user",
            content: `다음은 비디오의 청크별 개요들입니다:

${chunkOverviews.map((overview: any, index: number) =>
    `청크 ${index + 1}: ${overview.main_topic}\n핵심 포인트: ${
      overview.key_points.join(", ")
    }`
  ).join("\n\n")}

위 개요들을 통합하여 전체 구조를 분석해주세요.`,
          },
        ],
        max_tokens: 32768,
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error("OpenAI API 호출 실패", {
        status: response.status,
        statusText: response.statusText,
        error: errorText,
      });
      throw new Error(`OpenAI API 호출 실패: ${response.status}`);
    }

    const result = await response.json();
    const content = result.choices[0].message.content;

    try {
      const integratedStructure = JSON.parse(content);
      logger.info("전체 구조 통합 성공");
      return integratedStructure;
    } catch (parseError) {
      logger.error("JSON 파싱 실패", {content, error: parseError});
      return {
        overall_structure: "구조 분석 실패",
        main_themes: ["분석 실패"],
        flow_analysis: "흐름 분석 실패",
        key_transitions: [],
      };
    }
  } catch (error) {
    logger.error("integrateChunkOverviews 오류", {
      error: (error as Error).message,
    });
    throw new Error(`전체 구조 통합 실패: ${(error as Error).message}`);
  }
});

/**
 * 최종 요약 생성을 위한 Firebase Function
 */
export const generateFinalSummary = onCall(async (request) => {
  try {
    logger.info("generateFinalSummary 호출됨", {structuredData: true});

    if (!OPENAI_API_KEY) {
      throw new Error("OpenAI API 키가 설정되지 않았습니다.");
    }

    const {selectedSegments, overallStructure} = request.data;

    if (!selectedSegments || selectedSegments.length === 0) {
      return "선택된 세그먼트가 없습니다.";
    }

    // OpenAI API 호출
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `당신은 비디오 콘텐츠 요약 전문가입니다. 
선택된 세그먼트들을 바탕으로 간결하고 명확한 요약을 작성해주세요.

요약은 다음 조건을 만족해야 합니다:
- 3-5문장으로 간결하게 작성
- 핵심 내용만 포함
- 자연스러운 한국어로 작성
- 시간 순서대로 정리`,
          },
          {
            role: "user",
            content: `전체 구조: ${JSON.stringify(overallStructure)}

선택된 세그먼트들:
${selectedSegments.map((seg: any) =>
    `[${seg.id}] ${seg.startSec}s-${seg.endSec}s: ${seg.text}`
  ).join("\n")}

위 내용을 바탕으로 요약을 작성해주세요.`,
          },
        ],
        max_tokens: 1000,
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error("OpenAI API 호출 실패", {
        status: response.status,
        statusText: response.statusText,
        error: errorText,
      });
      throw new Error(`OpenAI API 호출 실패: ${response.status}`);
    }

    const result = await response.json();
    const summary = result.choices[0].message.content;

    logger.info("최종 요약 생성 성공");
    return summary;
  } catch (error) {
    logger.error("generateFinalSummary 오류", {error: (error as Error).message});
    throw new Error(`최종 요약 생성 실패: ${(error as Error).message}`);
  }
});

// 크레딧 차감 함수 (보안 강화)
export const deductCredits = onRequest(async (req, res) => {
  try {
    // CORS 헤더 설정
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    // POST 메서드만 허용
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    // Authorization 헤더 검증
    const authHeader = req.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;

    // 요청 본문에서 cost 검증
    const {cost} = req.body;
    if (typeof cost !== "number" || cost <= 0) {
      res.status(400).json({
        error: "Bad Request: cost must be a positive number",
      });
      return;
    }

    // 트랜잭션으로 크레딧 차감
    const userRef = admin.firestore().collection("users").doc(uid);
    const newCredits = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists || typeof snap.data()?.credits !== "number") {
        throw new Error("No credits found for user");
      }
      const current = snap.data()?.credits;
      if (typeof current !== "number") {
        throw new Error("Invalid credits data");
      }
      if (current < cost) {
        throw new Error("Insufficient credits");
      }
      const updated = current - cost;
      tx.set(userRef, {credits: updated}, {merge: true});
      return updated;
    });

    logger.info("크레딧 차감 성공", {uid, cost, newCredits});
    res.json({credits: newCredits});
  } catch (error) {
    logger.error("deductCredits 오류", {error: (error as Error).message});
    if ((error as Error).message === "Insufficient credits") {
      res.status(429).json({error: "Insufficient credits"});
      return;
    }
    res.status(500).json({error: (error as Error).message});
  }
});

// 크레딧 조회 함수
export const getCredits = onRequest(async (req, res) => {
  try {
    // CORS 헤더 설정
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    // GET 메서드만 허용
    if (req.method !== "GET") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    // Authorization 헤더 검증
    const authHeader = req.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;

    // 사용자 크레딧 조회
    const userRef = admin.firestore().collection("users").doc(uid);
    const doc = await userRef.get();
    const userData = doc.data();
    const credits = doc.exists && typeof userData?.credits === "number" ?
      userData.credits :
      null;

    logger.info("크레딧 조회 성공", {uid, credits});
    res.json({credits});
  } catch (error) {
    logger.error("getCredits 오류", {error: (error as Error).message});
    res.status(500).json({error: (error as Error).message});
  }
});

// 크레딧 확인 함수 (비디오 길이 계산, 크레딧 계산, 작업 가능 여부 확인, 상세 정보 반환)
export const checkCredits = onRequest(async (req, res) => {
  try {
    // CORS 헤더 설정
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    // POST 메서드만 허용
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    // Authorization 헤더 검증
    const authHeader = req.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid;

    // 요청 본문에서 비디오 길이 검증
    const {duration} = req.body;
    if (typeof duration !== "number" || duration <= 0) {
      res.status(400).json({
        error: "Bad Request: duration must be a positive number",
      });
      return;
    }

    // 사용자 크레딧 조회
    const userRef = admin.firestore().collection("users").doc(uid);
    const doc = await userRef.get();
    const userData = doc.data();
    const currentCredits = doc.exists && typeof userData?.credits === "number" ?
      userData.credits :
      0;

    // 크레딧 계산 로직 (서버 사이드에서 안전하게 처리)
    const requiredCredits = calculateCreditsForDuration(duration);
    const shortage = Math.max(0, requiredCredits - currentCredits);
    const canPerform = currentCredits >= requiredCredits;

    // 메시지 생성
    let message: string;
    if (!doc.exists) {
      message = "사용자 정보를 찾을 수 없습니다.";
    } else if (canPerform) {
      message = "작업을 진행할 수 있습니다.";
    } else {
      message = `크레딧이 부족합니다. ${shortage} 크레딧이 더 필요합니다.`;
    }

    const response = {
      currentCredits,
      requiredCredits,
      canPerform,
      shortage,
      message,
      creditPolicy: {
        baseRate: 1.5, // 1.5분당 1크레딧
        minimumCredits: 1,
        description: "30초 이하: 1크레딧, 1분 30초 이하: 1크레딧, 이후 1.5분 단위로 계산",
      },
    };

    logger.info("크레딧 확인 성공", {uid, duration, ...response});
    res.json(response);
  } catch (error) {
    logger.error("checkCredits 오류", {error: (error as Error).message});
    res.status(500).json({error: (error as Error).message});
  }
});

/**
 * 크레딧 계산 헬퍼 함수 (서버 사이드에서만 사용)
 * @param {number} durationInSeconds - 비디오 길이 (초 단위)
 * @return {number} 필요한 크레딧 수
 */
function calculateCreditsForDuration(durationInSeconds: number): number {
  if (durationInSeconds <= 0) return 0;

  // 30초 이하는 1크레딧
  if (durationInSeconds <= 30) return 1;

  // 1분 30초 이하는 1크레딧 (0초~1분 29초)
  if (durationInSeconds <= 90) return 1;

  // 2분 30초 이하는 2크레딧 (1분 30초~2분 29초)
  if (durationInSeconds <= 150) return 2;

  // 그 이후는 1분 30초 단위로 계산
  // 예: 2분 30초~3분 59초 = 3크레딧, 4분~5분 29초 = 4크레딧
  const minutes = durationInSeconds / 60;
  const credits = Math.ceil(minutes / 1.5); // 1.5분 단위로 올림

  return credits;
}
