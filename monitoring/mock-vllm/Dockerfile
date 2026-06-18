FROM python:3.12-slim
COPY server.py /server.py
EXPOSE 8000
# args are accepted (e.g. --model X --mock) and simply ignored by the stub;
# the real vllm/vllm-openai image consumes the same flags. Same RGD, both modes.
ENTRYPOINT ["python", "/server.py"]
