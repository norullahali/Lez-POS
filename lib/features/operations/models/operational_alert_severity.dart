enum OperationalAlertSeverity {
  info,
  warning,
  critical;

  int get sortOrder => switch (this) {
        OperationalAlertSeverity.critical => 0,
        OperationalAlertSeverity.warning => 1,
        OperationalAlertSeverity.info => 2,
      };
}
