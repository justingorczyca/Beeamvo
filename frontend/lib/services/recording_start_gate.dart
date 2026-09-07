class RecordingStartGate {
  bool isStarting = false;
  bool _processingRequested = false;

  void begin() {
    isStarting = true;
    _processingRequested = false;
  }

  bool requestProcessing() {
    if (!isStarting) return false;
    _processingRequested = true;
    return true;
  }

  bool finish({required bool canProcess}) {
    final process = canProcess && _processingRequested;
    isStarting = false;
    _processingRequested = false;
    return process;
  }
}
