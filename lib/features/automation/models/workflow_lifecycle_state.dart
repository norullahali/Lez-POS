enum WorkflowLifecycleState {
  pending,
  reviewed,
  accepted,
  ignored,
  expired,
  completed,
}

extension WorkflowLifecycleStateX on WorkflowLifecycleState {
  bool get isVisible => switch (this) {
        WorkflowLifecycleState.pending => true,
        WorkflowLifecycleState.reviewed => true,
        WorkflowLifecycleState.accepted => true,
        WorkflowLifecycleState.ignored => false,
        WorkflowLifecycleState.expired => false,
        WorkflowLifecycleState.completed => false,
      };

  bool get allowsRefresh => switch (this) {
        WorkflowLifecycleState.pending => true,
        WorkflowLifecycleState.reviewed => true,
        WorkflowLifecycleState.accepted => false,
        WorkflowLifecycleState.ignored => false,
        WorkflowLifecycleState.expired => true,
        WorkflowLifecycleState.completed => false,
      };

  WorkflowLifecycleState? transitionTo(WorkflowLifecycleState next) {
    if (this == next) return next;
    return switch ((this, next)) {
      (WorkflowLifecycleState.pending, WorkflowLifecycleState.reviewed) => next,
      (WorkflowLifecycleState.pending, WorkflowLifecycleState.accepted) => next,
      (WorkflowLifecycleState.pending, WorkflowLifecycleState.ignored) => next,
      (WorkflowLifecycleState.pending, WorkflowLifecycleState.expired) => next,
      (WorkflowLifecycleState.reviewed, WorkflowLifecycleState.accepted) => next,
      (WorkflowLifecycleState.reviewed, WorkflowLifecycleState.ignored) => next,
      (WorkflowLifecycleState.reviewed, WorkflowLifecycleState.expired) => next,
      (WorkflowLifecycleState.accepted, WorkflowLifecycleState.completed) => next,
      (WorkflowLifecycleState.expired, WorkflowLifecycleState.pending) => next,
      _ => null,
    };
  }
}