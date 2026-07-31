const assert = require("node:assert/strict");
const test = require("node:test");

process.env.GOOGLE_PLACES_API_KEY = "test-server-key";
const functions = require("../index.js");

function request(uid, data, provider = "password") {
  return {
    data,
    auth: uid
      ? {uid, token: {firebase: {sign_in_provider: provider}}}
      : null,
  };
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => error.code === code);
}

test("Places callables reject missing and anonymous authentication", async () => {
  const data = {
    query: "Boston",
    sessionToken: "session-token-1",
    useCase: "event",
  };
  await expectCode(functions.placesAutocomplete.run(request(null, data)), "unauthenticated");
  await expectCode(
    functions.placesAutocomplete.run(request("guest", data, "anonymous")),
    "unauthenticated",
  );
});

test("autocomplete validates query and session token", async () => {
  await expectCode(
    functions.placesAutocomplete.run(
      request("validation-user", {
        query: "ab",
        sessionToken: "session-token-2",
        useCase: "event",
      }),
    ),
    "invalid-argument",
  );
  await expectCode(
    functions.placesAutocomplete.run(
      request("token-user", {
        query: "Boston",
        sessionToken: "short",
        useCase: "event",
      }),
    ),
    "invalid-argument",
  );
});

test("city autocomplete sends the city restriction and returns at most eight normalized results", async () => {
  let requestBody;
  global.fetch = async (_url, options) => {
    requestBody = JSON.parse(options.body);
    return {
      ok: true,
      status: 200,
      json: async () => ({
        suggestions: Array.from({length: 10}, (_, index) => ({
          placePrediction: {
            placeId: `place-${index}`,
            text: {text: `City ${index}, USA`},
            structuredFormat: {
              mainText: {text: `City ${index}`},
              secondaryText: {text: "USA"},
            },
          },
        })),
      }),
    };
  };

  const result = await functions.placesAutocomplete.run(
    request("city-user", {
      query: "Bost",
      sessionToken: "session-token-3",
      useCase: "groupCity",
    }),
  );

  assert.deepEqual(requestBody.includedPrimaryTypes, ["(cities)"]);
  assert.deepEqual(requestBody.includedRegionCodes, ["us"]);
  assert.equal(result.predictions.length, 8);
  assert.deepEqual(result.predictions[0], {
    placeId: "place-0",
    description: "City 0, USA",
    primaryText: "City 0",
    secondaryText: "USA",
  });
});

test("place details normalize city, region, address, and coordinates", async () => {
  global.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => ({
      id: "place-1",
      displayName: {text: "Boston Common"},
      formattedAddress: "Boston Common, Boston, MA 02108, USA",
      location: {latitude: 42.355, longitude: -71.0656},
      addressComponents: [
        {longText: "Boston", shortText: "Boston", types: ["locality"]},
        {
          longText: "Massachusetts",
          shortText: "MA",
          types: ["administrative_area_level_1"],
        },
      ],
    }),
  });

  const result = await functions.placeDetails.run(
    request("details-user", {
      placeId: "place-1",
      sessionToken: "session-token-4",
    }),
  );
  assert.equal(result.city, "Boston");
  assert.equal(result.regionCode, "MA");
  assert.equal(result.latitude, 42.355);
  assert.equal(result.longitude, -71.0656);
});

test("Google authorization failures map to a stable configuration error", async () => {
  global.fetch = async () => ({
    ok: false,
    status: 403,
    json: async () => ({error: {message: "billing disabled"}}),
  });
  await expectCode(
    functions.placesAutocomplete.run(
      request("google-error-user", {
        query: "Boston",
        sessionToken: "session-token-5",
        useCase: "event",
      }),
    ),
    "failed-precondition",
  );
});

test("rate limiting applies per authenticated user", async () => {
  for (let index = 0; index < 60; index += 1) {
    await expectCode(
      functions.placesAutocomplete.run(
        request("rate-user", {
          query: "ab",
          sessionToken: "session-token-6",
          useCase: "event",
        }),
      ),
      "invalid-argument",
    );
  }
  await expectCode(
    functions.placesAutocomplete.run(
      request("rate-user", {
        query: "ab",
        sessionToken: "session-token-6",
        useCase: "event",
      }),
    ),
    "resource-exhausted",
  );
});

test("missing server secret fails before a Google request", async () => {
  delete process.env.GOOGLE_PLACES_API_KEY;
  await expectCode(
    functions.placesAutocomplete.run(
      request("secret-user", {
        query: "Boston",
        sessionToken: "session-token-7",
        useCase: "event",
      }),
    ),
    "failed-precondition",
  );
  process.env.GOOGLE_PLACES_API_KEY = "test-server-key";
});

test("reverse geocoding rejects out-of-range coordinates", async () => {
  await expectCode(
    functions.reverseGeocode.run(
      request("coordinate-user", {latitude: 95, longitude: -71}),
    ),
    "invalid-argument",
  );
});
