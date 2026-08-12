#!/system/bin/sh
export PREFIX=/data/data/com.termux/files/usr
export LD_LIBRARY_PATH=$PREFIX/lib
export PATH=$PREFIX/bin:$PATH
export TMPDIR=/data/local/tmp

CONFIG_FILE="/data/data/com.termux/files/home/Projects/native-ai/config.env"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    MODEL_PATH="/data/data/com.termux/files/home/models/phi-3-mini-q4.gguf"
    PORT=57160
    THREADS=4
    CONTEXT_SIZE=2048
fi

# Run llama-server with the configured parameters
exec llama-server -m "$MODEL_PATH" --port "$PORT" --threads "$THREADS" -c "$CONTEXT_SIZE"
