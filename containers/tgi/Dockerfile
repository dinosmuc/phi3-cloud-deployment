FROM ghcr.io/huggingface/text-generation-inference:3.1.1

RUN /usr/src/.venv/bin/huggingface-cli download \
      microsoft/Phi-3-mini-4k-instruct \
      --local-dir /data/models/phi3

ENV MODEL_ID=/data/models/phi3