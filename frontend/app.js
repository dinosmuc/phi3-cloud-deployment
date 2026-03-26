const API_URL = "${alb_url}";

let apiKey = "";
let isGenerating = false;

// DOM elements
const apiKeyInput = document.getElementById("apiKeyInput");
const connectBtn = document.getElementById("connectBtn");
const apiKeyBar = document.getElementById("apiKeyBar");
const status = document.getElementById("status");
const messages = document.getElementById("messages");
const userInput = document.getElementById("userInput");
const sendBtn = document.getElementById("sendBtn");

// Connect with API key
connectBtn.addEventListener("click", () => {
    const key = apiKeyInput.value.trim();
    if (!key) return;

    apiKey = key;
    apiKeyBar.classList.add("hidden");
    status.textContent = "Connected";
    status.className = "status connected";
    userInput.disabled = false;
    sendBtn.disabled = false;
    userInput.focus();
});

// Send on Enter (Shift+Enter for new line)
userInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
});

// Send button click
sendBtn.addEventListener("click", sendMessage);

// Auto-resize textarea
userInput.addEventListener("input", () => {
    userInput.style.height = "auto";
    userInput.style.height = Math.min(userInput.scrollHeight, 120) + "px";
});

function addMessage(role, text) {
    const div = document.createElement("div");
    div.className = "message " + role;
    div.textContent = text;
    messages.appendChild(div);
    messages.scrollTop = messages.scrollHeight;
    return div;
}

async function sendMessage() {
    const text = userInput.value.trim();
    if (!text || isGenerating) return;

    // Add user message
    addMessage("user", text);
    userInput.value = "";
    userInput.style.height = "auto";

    // Disable input while generating
    isGenerating = true;
    sendBtn.disabled = true;
    userInput.disabled = true;
    status.textContent = "Generating...";
    status.className = "status connecting";

    // Create assistant message bubble
    const assistantDiv = addMessage("assistant", "");

    try {
        const response = await fetch(API_URL + "/generate_stream", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": apiKey
            },
            body: JSON.stringify({
                inputs: text,
                parameters: {
                    max_new_tokens: 512,
                    temperature: 0.7,
                    top_p: 0.9
                }
            })
        });

        // Handle errors
        if (response.status === 401) {
            assistantDiv.remove();
            addMessage("error", "Invalid API key. Refresh the page and try again.");
            resetInput();
            return;
        }

        if (response.status === 503) {
            assistantDiv.textContent = "Service is starting up (~3-5 min). Retrying...";
            await retryUntilReady(text, assistantDiv);
            return;
        }

        if (!response.ok) {
            assistantDiv.remove();
            addMessage("error", "Error: " + response.status + " " + response.statusText);
            resetInput();
            return;
        }

        // Read SSE stream
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let fullText = "";

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            const chunk = decoder.decode(value, { stream: true });
            const lines = chunk.split("\n");

            for (const line of lines) {
                if (line.startsWith("data:")) {
                    const data = line.slice(5).trim();
                    if (data === "[DONE]") continue;

                    try {
                        const parsed = JSON.parse(data);
                        if (parsed.token && parsed.token.text) {
                            fullText += parsed.token.text;
                            assistantDiv.textContent = fullText;
                            messages.scrollTop = messages.scrollHeight;
                        }
                    } catch (e) {
                        // Skip malformed JSON lines
                    }
                }
            }
        }

        if (!fullText) {
            assistantDiv.textContent = "(Empty response)";
        }

    } catch (error) {
        assistantDiv.remove();
        if (error.name === "TypeError" && error.message.includes("Failed to fetch")) {
            addMessage("error", "Cannot reach the API. The service may be starting up. Please wait and try again.");
        } else {
            addMessage("error", "Error: " + error.message);
        }
    }

    resetInput();
}

async function retryUntilReady(text, messageDiv) {
    let attempts = 0;
    const maxAttempts = 20;

    while (attempts < maxAttempts) {
        attempts++;
        messageDiv.textContent = "Service is starting up... Retry " + attempts + "/" + maxAttempts + " (waiting 15s)";
        messages.scrollTop = messages.scrollHeight;

        await new Promise(resolve => setTimeout(resolve, 15000));

        try {
            const response = await fetch(API_URL + "/health");
            if (response.ok) {
                messageDiv.remove();
                // Service is ready, resend the original message
                userInput.value = text;
                isGenerating = false;
                sendBtn.disabled = false;
                userInput.disabled = false;
                sendMessage();
                return;
            }
        } catch (e) {
            // Still not ready
        }
    }

    messageDiv.remove();
    addMessage("error", "Service did not start after " + maxAttempts + " retries. Please try again later.");
    resetInput();
}

function resetInput() {
    isGenerating = false;
    sendBtn.disabled = false;
    userInput.disabled = false;
    status.textContent = "Connected";
    status.className = "status connected";
    userInput.focus();
}