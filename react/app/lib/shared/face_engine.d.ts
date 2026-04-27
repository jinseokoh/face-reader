// Hand-written type stub for the dart compile js artifact (face_engine.js).
// The compiled bundle is an IIFE that assigns `runEngine` onto the global
// object. Importing the .js file runs the IIFE; the function is then callable
// via `globalThis.runEngine`.

declare global {
  // eslint-disable-next-line no-var
  var runEngine: (metricsJson: string) => string;
}

export {};
