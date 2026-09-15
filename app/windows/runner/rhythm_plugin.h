#ifndef RHYTHM_PLUGIN_H_
#define RHYTHM_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>

#include <mmdeviceapi.h>
#include <audioclient.h>

namespace lxplayer {

class RhythmPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

  RhythmPlugin(flutter::BinaryMessenger* messenger);
  virtual ~RhythmPlugin();

  friend class RhythmStreamHandler;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartCapture();
  void StopCapture();
  void CaptureThread();

  // Audio Capture Implementation
  void ProcessAudioData(float* buffer, uint32_t frames, uint32_t channels);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  std::thread capture_thread_;
  std::atomic<bool> is_capturing_{false};
  
  // FFT state
  std::vector<float> fft_magnitudes_;
  std::mutex magnitude_mutex_;
};

class RhythmStreamHandler : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  RhythmStreamHandler(RhythmPlugin* plugin) : plugin_(plugin) {}
  
 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override {
    plugin_->event_sink_ = std::move(events);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
      const flutter::EncodableValue* arguments) override {
    plugin_->event_sink_ = nullptr;
    return nullptr;
  }

 private:
  RhythmPlugin* plugin_;
};

}  // namespace lxplayer

#endif  // RHYTHM_PLUGIN_H_
