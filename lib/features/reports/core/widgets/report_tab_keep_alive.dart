import 'package:flutter/material.dart';

/// Preserves tab subtree state (scroll, filters UI) when switching report tabs.
class ReportTabKeepAlive extends StatefulWidget {
  const ReportTabKeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<ReportTabKeepAlive> createState() => _ReportTabKeepAliveState();
}

class _ReportTabKeepAliveState extends State<ReportTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}