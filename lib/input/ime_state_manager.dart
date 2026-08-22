import 'dart:async';
import 'package:flutter/services.dart';


class ImeStateManager {
  String preeditText = '';
  String preeditFragmentId = '';
  int preeditLocalOffset = 0;
  String preeditContainerId = '';
  int preeditCaretOffset = 0;

  bool isComposing = false;
  TextRange composingRange = TextRange.empty;

  bool updatingSelf = false;
  bool justHandledEnter = false;
  bool justCommittedComposition = false;
  String lastCommittedText = '';
  String lastSyncedFragmentId = '';
  String lastSyncedText = '';
  String prevSelectionKey = '';
  String? staleImeText;

  Timer? structuralChangeTimer;
  bool structuralChangeInProgress = false;
  static const Duration structuralChangeGracePeriod = Duration(
    milliseconds: 300,
  );

  void resetComposition() {
    isComposing = false;
    preeditText = '';
    composingRange = TextRange.empty;
    preeditFragmentId = '';
    preeditLocalOffset = 0;
    preeditContainerId = '';
    preeditCaretOffset = 0;
  }

  void attachInput() {
    lastSyncedFragmentId = '';
    lastSyncedText = '';
    prevSelectionKey = '';
    justCommittedComposition = false;
    lastCommittedText = '';
  }

  void detachInput() {
    structuralChangeTimer?.cancel();
    structuralChangeTimer = null;
    structuralChangeInProgress = false;
    resetComposition();
    lastSyncedFragmentId = '';
    lastSyncedText = '';
    prevSelectionKey = '';
    justCommittedComposition = false;
    lastCommittedText = '';
  }

  bool isPreeditInContainer(String containerId) {
    return isComposing && preeditContainerId == containerId;
  }
}
