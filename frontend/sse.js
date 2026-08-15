// Server-Sent Events parsing, kept out of app.js so it can be unit-tested with
// node --test. Loaded as a plain script before app.js — no build step, and unlike
// app.js this file is never rendered through Terraform's templatefile().

// Reassembles an SSE stream from arbitrary network chunks.
//
// A chunk boundary can fall anywhere, including the middle of a JSON event. Parsing
// each chunk on its own therefore drops tokens: the first half fails to parse and
// the second half no longer starts with "data:". Holding the unfinished tail back
// until the rest of it arrives is what makes the stream lossless.
class SSEBuffer {
    constructor() {
        this.tail = "";
    }

    // Feed one decoded chunk; returns the complete data payloads it completed.
    push(chunk) {
        const lines = (this.tail + chunk).split("\n");

        // Whatever follows the last newline is unfinished — either a partial line,
        // or "" when the chunk happened to end on a line boundary. Keep it for the
        // next call rather than parsing it now.
        this.tail = lines.pop();

        const payloads = [];

        for (const line of lines) {
            if (!line.startsWith("data:")) continue;

            const data = line.slice(5).trim();
            if (data.length > 0) payloads.push(data);
        }

        return payloads;
    }
}

// The browser picks SSEBuffer up as a global; this export is only for node --test.
if (typeof module !== "undefined") module.exports = { SSEBuffer };
