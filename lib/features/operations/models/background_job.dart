typedef BackgroundJobHandler = Future<void> Function();

class BackgroundJob {
  const BackgroundJob({
    required this.id,
    required this.labelAr,
    required this.handler,
    this.interval,
    this.runOnStartup = false,
  });

  final String id;
  final String labelAr;
  final BackgroundJobHandler handler;
  final Duration? interval;
  final bool runOnStartup;
}
