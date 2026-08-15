const test = require("node:test");
const assert = require("node:assert");

const { SSEBuffer } = require("../frontend/sse.js");

// Feed a stream to the buffer one chunk at a time and collect what comes out.
function collect(chunks) {
    const sse = new SSEBuffer();
    const payloads = [];

    for (const chunk of chunks) payloads.push(...sse.push(chunk));

    return payloads;
}

// Join the token text out of the payloads, the way app.js renders it.
function tokens(payloads) {
    return payloads
        .filter(payload => payload !== "[DONE]")
        .map(payload => JSON.parse(payload).choices[0].delta.content)
        .join("");
}

const STREAM =
    'data: {"choices":[{"delta":{"content":"a"}}]}\n\n' +
    'data: {"choices":[{"delta":{"content":"b"}}]}\n\n' +
    'data: {"choices":[{"delta":{"content":"c"}}]}\n\n' +
    "data: [DONE]\n\n";

test("an event split across two chunks is reconstructed", () => {
    const event = 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n';

    // Cut in the middle of the JSON — the old parser dropped this token silently.
    const payloads = collect([event.slice(0, 30), event.slice(30)]);

    assert.strictEqual(payloads.length, 1);
    assert.strictEqual(tokens(payloads), "Hello");
});

test("no token is lost at any chunk boundary", () => {
    for (let cut = 1; cut < STREAM.length; cut++) {
        const payloads = collect([STREAM.slice(0, cut), STREAM.slice(cut)]);

        assert.strictEqual(tokens(payloads), "abc", "split at index " + cut);
    }
});

test("several events arriving in one chunk are all returned", () => {
    const payloads = collect([STREAM]);

    assert.strictEqual(payloads.length, 4);
    assert.strictEqual(payloads[3], "[DONE]");
});

test("an unfinished event is held back until the rest arrives", () => {
    const sse = new SSEBuffer();

    assert.deepStrictEqual(sse.push('data: {"choices":[{"delta"'), []);
    assert.deepStrictEqual(sse.push(':{"content":"x"}}]}\n\n'), [
        '{"choices":[{"delta":{"content":"x"}}]}',
    ]);
});
