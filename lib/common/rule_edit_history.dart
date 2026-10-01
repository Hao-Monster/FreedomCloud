/// Bounded document history; checkpoints are explicit user operations.
class RuleEditHistory {
  RuleEditHistory(String initial) : _versions = [initial];
  final List<String> _versions;
  int _index = 0;
  String get current => _versions[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index + 1 < _versions.length;
  void record(String document) {
    if (document == current) return;
    _versions.removeRange(_index + 1, _versions.length);
    _versions.add(document);
    while (_versions.length > 20 ||
        (_versions.length > 1 && _versions.fold<int>(0, (n, v) => n + v.length) > 8000000)) {
      _versions.removeAt(0);
    }
    _index = _versions.length - 1;
  }
  String undo() => _versions[canUndo ? --_index : _index];
  String redo() => _versions[canRedo ? ++_index : _index];
}
