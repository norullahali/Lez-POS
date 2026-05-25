enum OperationalAlertState {
  active,
  acknowledged,
  resolved,
  archived;

  String get labelAr => switch (this) {
        OperationalAlertState.active => 'نشط',
        OperationalAlertState.acknowledged => 'مُقرّ',
        OperationalAlertState.resolved => 'محلول',
        OperationalAlertState.archived => 'مؤرشف',
      };

  bool get isVisibleInInbox =>
      this == OperationalAlertState.active ||
      this == OperationalAlertState.acknowledged;

  bool get countsAsUnread => this == OperationalAlertState.active;
}