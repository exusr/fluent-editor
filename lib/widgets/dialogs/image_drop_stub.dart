import 'package:flutter/material.dart';

class WebDropTarget extends StatelessWidget {
  final Widget child;
  final void Function(List<int> bytes, String fileName, String extension)? onFileDropped;

  const WebDropTarget({
    super.key,
    required this.child,
    this.onFileDropped,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
