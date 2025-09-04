#ifndef FIREBASE_OPTIONS_H
#define FIREBASE_OPTIONS_H

#include "firebase/app.h"

namespace firebase {
namespace app {

// Firebase 설정
const char kDefaultAppName[] = "[DEFAULT]";

// Your web app's Firebase configuration
const char kDefaultAppOptions[] = R"({
  "apiKey": "AIzaSyA6dzIJCfSmWRV3KB9irzgVt0iNziYQR00",
  "authDomain": "bestcut-beta.firebaseapp.com",
  "projectId": "bestcut-beta",
  "storageBucket": "bestcut-beta.firebasestorage.app",
  "messagingSenderId": "27116968071",
  "appId": "1:27116968071:web:83b829c095e18c4f2e0022",
  "measurementId": "G-2KWBLRG36F"
})";

}  // namespace app
}  // namespace firebase

#endif  // FIREBASE_OPTIONS_H