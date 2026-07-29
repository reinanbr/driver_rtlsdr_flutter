#include "audio_sink.h"

#include <oboe/Oboe.h>

#include <cstring>
#include <memory>

namespace {

class PullCallback : public oboe::AudioStreamDataCallback {
public:
    PullCallback(audio_pull_cb_t cb, void *user_data, int channel_count)
        : cb_(cb), user_data_(user_data), channel_count_(channel_count) {}

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream * /*stream*/, void *audio_data,
                                           int32_t num_frames) override {
        auto *out = static_cast<int16_t *>(audio_data);
        size_t frames = static_cast<size_t>(num_frames);
        size_t filled = cb_ ? cb_(out, frames, user_data_) : 0;
        if (filled < frames) {
            /* Underrun: zera o restante em AMOSTRAS, não frames — cada
             * frame tem channel_count_ amostras int16 (bug fácil de
             * esquecer em estéreo: multiplicar só por sizeof(int16_t)
             * deixaria metade do buffer de underrun com lixo). */
            std::memset(out + filled * channel_count_, 0, (frames - filled) * channel_count_ * sizeof(int16_t));
        }
        return oboe::DataCallbackResult::Continue;
    }

private:
    audio_pull_cb_t cb_;
    void *user_data_;
    int channel_count_;
};

std::shared_ptr<oboe::AudioStream> g_stream;
std::unique_ptr<PullCallback> g_callback;

}  // namespace

extern "C" int audio_sink_start(uint32_t sample_rate_hz, int channel_count, audio_pull_cb_t pull_cb,
                                 void *user_data) {
    if (g_stream) {
        return -1; /* já em execução */
    }
    if (channel_count != 1 && channel_count != 2) {
        return -1;
    }

    g_callback = std::make_unique<PullCallback>(pull_cb, user_data, channel_count);

    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        // SharingMode::Shared (não Exclusive) por simplicidade no M3 — mais
        // amplamente suportado entre fabricantes, sem precisar de fallback.
        // Revisitar Exclusive+fallback se a latência não for boa o
        // suficiente na prática.
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setFormat(oboe::AudioFormat::I16)
        ->setChannelCount(channel_count == 2 ? oboe::ChannelCount::Stereo : oboe::ChannelCount::Mono)
        ->setSampleRate(static_cast<int32_t>(sample_rate_hz))
        ->setDataCallback(g_callback.get());

    oboe::Result result = builder.openStream(g_stream);
    if (result != oboe::Result::OK) {
        g_stream.reset();
        g_callback.reset();
        return -1;
    }

    result = g_stream->requestStart();
    if (result != oboe::Result::OK) {
        g_stream->close();
        g_stream.reset();
        g_callback.reset();
        return -1;
    }

    return 0;
}

extern "C" void audio_sink_stop(void) {
    if (!g_stream) {
        return;
    }
    g_stream->requestStop();
    g_stream->close();
    g_stream.reset();
    g_callback.reset();
}
