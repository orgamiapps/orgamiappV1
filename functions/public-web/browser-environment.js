"use strict";

// Public Firebase identifiers; never provider credentials. Unknown projects fail
// closed rather than mixing staging data with production authentication.
const PROJECTS = {
  "orgami-66nxok": {
    apiKey: "AIzaSyA-PFyqhP5aEVE6XwGku3jMe91G3efMaVw", authDomain: "attendus.app",
    projectId: "orgami-66nxok", appId: "1:951311475019:web:65b1de24d2f3a8d289c8ce",
    messagingSenderId: "951311475019",
  },
  "attendus-staging": {
    apiKey: "AIzaSyBCFt_7BJNVVzgAZ2Fa7S_5UMGYIVDQ-dg", authDomain: "attendus-staging.firebaseapp.com",
    projectId: "attendus-staging", appId: "1:925344893088:web:3be71e809ba516e1d021c5",
    messagingSenderId: "925344893088",
  },
};

function browserEnvironment(env = process.env) {
  require("./origin").publicOrigin(env);
  const project = env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT;
  if (env.FUNCTIONS_EMULATOR === "true" && project === "demo-attendus-admin") {
    return {
      firebase: {apiKey: "demo-only-key", authDomain: "localhost", projectId: project,
        appId: "1:123456789:web:demo", messagingSenderId: "123456789"},
      emulators: {host: "127.0.0.1", authPort: 9190, functionsPort: 5101},
      connectSources: ["http://127.0.0.1:9190", "http://127.0.0.1:5101"],
    };
  }
  const firebase = PROJECTS[project];
  if (!firebase) throw new Error("Public web requires an explicit supported Firebase project.");
  return {firebase: {...firebase}, connectSources: [`https://us-central1-${project}.cloudfunctions.net`]};
}

module.exports = {browserEnvironment};
