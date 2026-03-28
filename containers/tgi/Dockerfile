FROM ghcr.io/huggingface/text-generation-inference:2.4.1

RUN pip install huggingface_hub && \
    huggingface-cli download \
      Sreenington/Phi-3-mini-4k-instruct-AWQ \
      --local-dir /data/models/phi3-awq

ENV MODEL_ID=/data/models/phi3-awq