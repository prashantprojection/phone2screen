/// Workspace complexity mode controlling Simple webcam vs full Studio UI.
enum WorkspaceMode {
  simple,
  studio;

  /// Short display label shown in workspace mode switchers and badges.
  String get label => switch (this) {
    .simple => 'Simple',
    .studio => 'Studio',
  };

  /// Concise description of what this workspace mode surfaces.
  String get description => switch (this) {
    .simple => 'Plug-and-play webcam for Zoom, Meet, Teams & Discord',
    .studio => 'Multi-cam grid, OBS WebSocket tally & full studio rig',
  };
}
