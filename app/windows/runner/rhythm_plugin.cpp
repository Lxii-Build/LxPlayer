#include "rhythm_plugin.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <endpointvolume.h>
#include <functiondiscoverykeys_devpkey.h>
#include <iostream>
#include <cmath>
#include <algorithm>
#include <complex>

#pragma comment(lib, "Ole32.lib")

namespace lxplayer {

namespace {
    const int FFT_SIZE = 1024;
    const int BANDS_COUNT = 16;
    const float PI = 3.14159265358979323846f;

    // Simple FFT implementation
    void fft(std::vector<std::complex<float>>& a) {
        size_t n = a.size();
        for (size_t i = 1, j = 0; i < n; i++) {
            size_t bit = n >> 1;
            for (; j & bit; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) std::swap(a[i], a[j]);
        }
        for (int len = 2; len <= n; len <<= 1) {
            float ang = 2 * PI / len;
            std::complex<float> wlen(std::cos(ang), std::sin(ang));
            for (int i = 0; i < n; i += len) {
                std::complex<float> w(1);
                for (int j = 0; j < len / 2; j++) {
                    std::complex<float> u = a[i + j], v = a[i + j + len / 2] * w;
                    a[i + j] = u + v;
                    a[i + j + len / 2] = u - v;
                    w *= wlen;
                }
            }
        }
    }
}

void RhythmPlugin::RegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar_ref) {
  auto registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);

  auto plugin = std::make_unique<RhythmPlugin>(registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

RhythmPlugin::RhythmPlugin(flutter::BinaryMessenger* messenger) {
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "cc.lxii.player/rhythm_method",
      &flutter::StandardMethodCodec::GetInstance());
  
  event_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "cc.lxii.player/rhythm_event",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const auto &call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  auto handler = std::make_unique<RhythmStreamHandler>(this);
  event_channel_->SetStreamHandler(std::move(handler));

  fft_magnitudes_.resize(BANDS_COUNT, 0.0f);
}

RhythmPlugin::~RhythmPlugin() {
  StopCapture();
}

void RhythmPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "start") {
    StartCapture();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "stop") {
    StopCapture();
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

void RhythmPlugin::StartCapture() {
  if (is_capturing_) return;
  is_capturing_ = true;
  capture_thread_ = std::thread(&RhythmPlugin::CaptureThread, this);
}

void RhythmPlugin::StopCapture() {
  is_capturing_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
}

void RhythmPlugin::CaptureThread() {
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(hr)) return;

    IMMDeviceEnumerator* enumerator = NULL;
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), (void**)&enumerator);
    if (FAILED(hr)) { CoUninitialize(); return; }

    IMMDevice* device = NULL;
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
    if (FAILED(hr)) { enumerator->Release(); CoUninitialize(); return; }

    IAudioClient* audioClient = NULL;
    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, NULL, (void**)&audioClient);
    if (FAILED(hr)) { device->Release(); enumerator->Release(); CoUninitialize(); return; }

    WAVEFORMATEX* pwfx = NULL;
    hr = audioClient->GetMixFormat(&pwfx);
    if (FAILED(hr)) { audioClient->Release(); device->Release(); enumerator->Release(); CoUninitialize(); return; }

    hr = audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 0, 0, pwfx, NULL);
    if (FAILED(hr)) { CoTaskMemFree(pwfx); audioClient->Release(); device->Release(); enumerator->Release(); CoUninitialize(); return; }

    IAudioCaptureClient* captureClient = NULL;
    hr = audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&captureClient);
    if (FAILED(hr)) { CoTaskMemFree(pwfx); audioClient->Release(); device->Release(); enumerator->Release(); CoUninitialize(); return; }

    hr = audioClient->Start();
    if (FAILED(hr)) { captureClient->Release(); CoTaskMemFree(pwfx); audioClient->Release(); device->Release(); enumerator->Release(); CoUninitialize(); return; }

    std::vector<float> pcm_buffer;
    pcm_buffer.reserve(FFT_SIZE);

    while (is_capturing_) {
        UINT32 nextPacketSize = 0;
        hr = captureClient->GetNextPacketSize(&nextPacketSize);
        if (FAILED(hr)) break;

        while (nextPacketSize != 0) {
            BYTE* data = NULL;
            UINT32 framesAvailable = 0;
            DWORD flags = 0;

            hr = captureClient->GetBuffer(&data, &framesAvailable, &flags, NULL, NULL);
            if (FAILED(hr)) break;

            if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT)) {
                // Assuming float-32 format from GetMixFormat loopback
                float* fData = (float*)data;
                for (UINT32 i = 0; i < framesAvailable; i++) {
                    // Mono mix
                    float sample = 0;
                    for (int c = 0; c < pwfx->nChannels; c++) {
                        sample += fData[i * pwfx->nChannels + c];
                    }
                    sample /= pwfx->nChannels;
                    pcm_buffer.push_back(sample);

                    if (pcm_buffer.size() >= FFT_SIZE) {
                        ProcessAudioData(pcm_buffer.data(), FFT_SIZE, 1);
                        pcm_buffer.clear();
                    }
                }
            } else {
                // Silent buffer, clear FFT
                std::lock_guard<std::mutex> lock(magnitude_mutex_);
                std::fill(fft_magnitudes_.begin(), fft_magnitudes_.end(), 0.0f);
            }

            hr = captureClient->ReleaseBuffer(framesAvailable);
            if (FAILED(hr)) break;

            hr = captureClient->GetNextPacketSize(&nextPacketSize);
            if (FAILED(hr)) break;
        }

        // Send data to Flutter
        if (event_sink_) {
            std::lock_guard<std::mutex> lock(magnitude_mutex_);
            flutter::EncodableList bands;
            for (float m : fft_magnitudes_) {
                bands.push_back(flutter::EncodableValue(static_cast<double>(m)));
            }
            event_sink_->Success(flutter::EncodableValue(bands));
        }

        Sleep(16); // ~60fps
    }

    audioClient->Stop();
    captureClient->Release();
    CoTaskMemFree(pwfx);
    audioClient->Release();
    device->Release();
    enumerator->Release();
    CoUninitialize();
}

void RhythmPlugin::ProcessAudioData(float* buffer, uint32_t frames, uint32_t channels) {
    std::vector<std::complex<float>> data(FFT_SIZE);
    for (int i = 0; i < FFT_SIZE; i++) {
        // Hanning window
        float window = 0.5f * (1 - std::cos(2 * PI * i / (FFT_SIZE - 1)));
        data[i] = std::complex<float>(buffer[i] * window, 0);
    }

    fft(data);

    std::lock_guard<std::mutex> lock(magnitude_mutex_);
    
    // Group into bands
    int samplesPerBand = (FFT_SIZE / 2) / BANDS_COUNT;
    for (int b = 0; b < BANDS_COUNT; b++) {
        float sum = 0;
        for (int i = 0; i < samplesPerBand; i++) {
            sum += std::abs(data[b * samplesPerBand + i]);
        }
        float avg = sum / samplesPerBand;
        
        // Logarithmic scale & Normalization (Roughly)
        float normalized = std::clamp(avg * 10.0f, 0.0f, 1.0f);
        
        // Decay for smoothness if needed, or let Flutter handle it
        fft_magnitudes_[b] = normalized;
    }
}

}  // namespace lxplayer
