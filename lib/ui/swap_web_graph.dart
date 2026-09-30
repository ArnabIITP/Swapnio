import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import 'swapnio_widgets.dart';

/// One person on a Swap Web map (see functions/web.js mySwapWeb).
class WebNode {
  final String key;
  final String? id;
  final String name;
  final String photoUrl;
  final bool verified;

  /// 0 = you; 1 = linked to you directly; 2+ = further out.
  final int depth;
  final String? parent;

  /// Minutes spent with their parent.
  final int minutes;

  const WebNode({
    required this.key,
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.depth,
    required this.parent,
    required this.minutes,
    this.verified = false,
  });

  factory WebNode.fromMap(Map<String, dynamic> m) => WebNode(
    key: m['key'] as String,
    id: m['id'] as String?,
    name: (m['name'] as String?) ?? '',
    photoUrl: (m['photoUrl'] as String?) ?? '',
    verified: m['verified'] == true,
    depth: (m['depth'] as num?)?.toInt() ?? 0,
    parent: m['parent'] as String?,
    minutes: (m['minutes'] as num?)?.toInt() ?? 0,
  );
}

/// One skill taught along a line, with the time spent on it.
class WebSkill {
  final String skill;
  final int minutes;
  final int sessions;

  const WebSkill(this.skill, this.minutes, this.sessions);

  factory WebSkill.fromMap(Map<String, dynamic> m) => WebSkill(
    (m['skill'] as String?) ?? '',
    (m['minutes'] as num?)?.toInt() ?? 0,
    (m['sessions'] as num?)?.toInt() ?? 0,
  );
}

/// The line between two people. "mutual": each has taught the other
/// ([forward] = what [from] taught [to], [back] = the reverse). "oneway":
/// only [from] has taught [to] ([back] is empty).
class WebEdge {
  final String from;
  final String to;
  final String kind;
  final List<WebSkill> forward;
  final List<WebSkill> back;
  final int minutes;
  final int sessions;

  const WebEdge({
    required this.from,
    required this.to,
    required this.minutes,
    required this.sessions,
    this.kind = 'oneway',
    this.forward = const [],
    this.back = const [],
  });

  bool get isMutual => kind == 'mutual';
  bool touches(String key) => from == key || to == key;
  String other(String key) => from == key ? to : from;

  /// What [teacher] taught along this line.
  List<WebSkill> taughtBy(String teacher) => teacher == from
      ? forward
      : teacher == to
      ? back
      : const [];

  List<String> get skills => {
    for (final x in [...forward, ...back]) x.skill,
  }.toList();

  static List<WebSkill> _skills(Object? v) => [
    for (final x in (v as List? ?? const []))
      WebSkill.fromMap(Map<String, dynamic>.from(x as Map)),
  ];

  factory WebEdge.fromMap(Map<String, dynamic> m) => WebEdge(
    from: m['from'] as String,
    to: m['to'] as String,
    kind: (m['kind'] as String?) ?? 'oneway',
    forward: _skills(m['forward']),
    back: _skills(m['back']),
    minutes: (m['minutes'] as num?)?.toInt() ?? 0,
    sessions: (m['sessions'] as num?)?.toInt() ?? 0,
  );
}

class SwapWebData {
  final List<WebNode> nodes;
  final List<WebEdge> edges;
  final int people;
  final int taughtMinutes;
  final int learnedMinutes;
  final bool capped;

  const SwapWebData({
    required this.nodes,
    required this.edges,
    required this.people,
    required this.taughtMinutes,
    required this.learnedMinutes,
    required this.capped,
  });

  factory SwapWebData.fromMap(Map<String, dynamic> m) {
    final summary = Map<String, dynamic>.from(m['summary'] as Map? ?? const {});
    return SwapWebData(
      nodes: [
        for (final n in (m['nodes'] as List? ?? const []))
          WebNode.fromMap(Map<String, dynamic>.from(n as Map)),
      ],
      edges: [
        for (final e in (m['edges'] as List? ?? const []))
          WebEdge.fromMap(Map<String, dynamic>.from(e as Map)),
      ],
      people: (summary['people'] as num?)?.toInt() ?? 0,
      taughtMinutes: (summary['taughtMinutes'] as num?)?.toInt() ?? 0,
      learnedMinutes: (summary['learnedMinutes'] as num?)?.toInt() ?? 0,
      capped: summary['capped'] == true,
    );
  }

  WebNode? get center => nodes.where((n) => n.depth == 0).firstOrNull;
  WebNode? node(String key) => nodes.where((n) => n.key == key).firstOrNull;
}

/// Dot diameter for [minutes] of time together (square-root scale, so a few
/// very long links don't swamp everyone else).
double nodeDiameter(
  int minutes,
  int maxMinutes, {
  double min = 30,
  double max = 52,
}) {
  if (maxMinutes <= 0) return min;
  return min + (max - min) * math.sqrt(minutes / maxMinutes).clamp(0.0, 1.0);
}

/// Every node's diameter for [data].
Map<String, double> webDiameters(SwapWebData data) {
  final maxMinutes = data.nodes
      .where((n) => n.depth > 0)
      .fold<int>(0, (m, n) => math.max(m, n.minutes));
  // Busy maps get smaller dots so everyone fits.
  final crowd = math.sqrt(12 / math.max(data.nodes.length, 12)).clamp(0.7, 1.0);
  return {
    for (final n in data.nodes)
      n.key: n.depth == 0 ? 56 : nodeDiameter(n.minutes, maxMinutes) * crowd,
  };
}

/// A small force simulation: people push each other apart, links pull like
/// springs, and a weak pull keeps everything near the middle (you most of
/// all). [step] advances one frame; [alpha] is the "temperature", cooling
/// each step until the web settles, and reheated when someone is dragged.
class WebSimulation {
  final SwapWebData data;
  Size size;
  final Map<String, Offset> pos = {};
  final Map<String, Offset> _vel = {};
  late final Map<String, double> diameters = webDiameters(data);
  double alpha = 1;

  /// A node being dragged: held under the finger, not moved by forces.
  String? pinned;

  static const double _repulsion = 9000;
  static const double _spring = 0.05;
  static const double _gravity = 0.012;
  static const double _friction = 0.55;
  static const double _cooling = 0.975;

  WebSimulation(this.data, this.size) {
    final c = size.center(Offset.zero);
    // Deterministic start (golden-angle spiral), so the same web settles
    // into the same picture - the share image and the passport match.
    var i = 0;
    for (final n in data.nodes) {
      if (n.depth == 0) {
        pos[n.key] = c;
      } else {
        final a = i * 2.39996 + n.depth;
        final r = 60.0 * n.depth + 14.0 * (i % 3);
        pos[n.key] = _clamp(n.key, c + Offset(math.cos(a), math.sin(a)) * r);
        i++;
      }
      _vel[n.key] = Offset.zero;
    }
  }

  bool get settled => alpha < 0.02 && pinned == null;

  void reheat([double to = 0.6]) => alpha = math.max(alpha, to);

  static const double _rest = 120;

  void step() {
    final keys = pos.keys.toList();
    final force = {for (final k in keys) k: Offset.zero};
    for (var i = 0; i < keys.length; i++) {
      for (var j = i + 1; j < keys.length; j++) {
        final a = keys[i];
        final b = keys[j];
        final d = pos[a]! - pos[b]!;
        final dist2 = math.max(d.distanceSquared, 64.0);
        final dist = math.sqrt(dist2);
        final push = (d / dist) * (_repulsion / dist2);
        force[a] = force[a]! + push;
        force[b] = force[b]! - push;
      }
    }
    for (final e in data.edges) {
      final a = pos[e.from];
      final b = pos[e.to];
      if (a == null || b == null) continue;
      final d = b - a;
      final dist = math.max(d.distance, 1.0);
      final pull = (d / dist) * ((dist - _rest) * _spring);
      force[e.from] = force[e.from]! + pull;
      force[e.to] = force[e.to]! - pull;
    }
    final c = size.center(Offset.zero);
    for (final n in data.nodes) {
      // You stay near the middle; everyone else is only loosely held.
      final g = n.depth == 0 ? _gravity * 12 : _gravity;
      force[n.key] = force[n.key]! + (c - pos[n.key]!) * g;
    }
    for (final k in keys) {
      if (k == pinned) {
        _vel[k] = Offset.zero;
        continue;
      }
      final v = (_vel[k]! + force[k]! * alpha) * _friction;
      _vel[k] = v;
      pos[k] = _clamp(k, pos[k]! + v);
    }
    _separate(keys);
    alpha *= _cooling;
  }

  /// No two dots overlap: pairs closer than their radii plus room for a name
  /// are pushed apart (a dragged dot holds its place).
  void _separate(List<String> keys) {
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final a = keys[i];
          final b = keys[j];
          final min = (diameters[a]! + diameters[b]!) / 2 + 16;
          final d = pos[b]! - pos[a]!;
          final dist = d.distance;
          if (dist >= min) continue;
          final dir = dist < 0.01 ? const Offset(1, 0.3) : d / dist;
          final push = dir * ((min - dist) / 2);
          if (a != pinned) {
            pos[a] = _clamp(a, pos[a]! - (b == pinned ? push * 2 : push));
          }
          if (b != pinned) {
            pos[b] = _clamp(b, pos[b]! + (a == pinned ? push * 2 : push));
          }
        }
      }
    }
  }

  /// Runs until settled - for the static share image and passport page.
  void settle([int steps = 320]) {
    for (var i = 0; i < steps; i++) {
      step();
    }
  }

  /// Keeps a dot (and its name under it) inside the canvas.
  Offset _clamp(String key, Offset p) {
    final r = (diameters[key] ?? 40) / 2;
    return Offset(
      p.dx.clamp(r + 18, math.max(r + 18, size.width - r - 18)),
      p.dy.clamp(r + 8, math.max(r + 8, size.height - r - 24)),
    );
  }

  void moveTo(String key, Offset p) => pos[key] = _clamp(key, p);

  /// The node under [p], if any (with a little slack for fingers).
  String? hit(Offset p) {
    String? best;
    var bestD = double.infinity;
    for (final e in pos.entries) {
      final d = (e.value - p).distance;
      final r = (diameters[e.key] ?? 40) / 2 + 8;
      if (d <= r && d < bestD) {
        best = e.key;
        bestD = d;
      }
    }
    return best;
  }
}

/// The live, draggable web: drag people around, tap one to focus on their
/// links (and hear about it through [onTapNode]), tap empty space to clear.
class SwapWebGraph extends StatefulWidget {
  final SwapWebData data;
  final void Function(WebNode node)? onTapNode;
  final double height;

  const SwapWebGraph({
    super.key,
    required this.data,
    this.onTapNode,
    this.height = 440,
  });

  @override
  State<SwapWebGraph> createState() => _SwapWebGraphState();
}

class _SwapWebGraphState extends State<SwapWebGraph>
    with SingleTickerProviderStateMixin {
  WebSimulation? _sim;
  late final Ticker _ticker = createTicker((_) => _tick());
  String? _selected;
  String? _dragging;
  double _dragDistance = 0;

  @override
  void didUpdateWidget(SwapWebGraph old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) {
      _sim = null;
      _selected = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  WebSimulation _simFor(Size size) {
    final sim = _sim;
    if (sim != null && sim.size == size) return sim;
    if (sim != null) {
      // Re-fit to a new width (rotation, window resize).
      sim.size = size;
      sim.reheat(0.4);
    } else {
      _sim = WebSimulation(widget.data, size);
    }
    _wake();
    return _sim!;
  }

  void _wake() {
    if (!_ticker.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ticker.isActive) _ticker.start();
      });
    }
  }

  void _tick() {
    final sim = _sim;
    if (sim == null) return;
    sim.step();
    if (sim.settled) _ticker.stop();
    setState(() {});
  }

  void _onDragStart(Offset local) {
    final sim = _sim;
    if (sim == null) return;
    _dragging = sim.hit(local);
    _dragDistance = 0;
    sim.pinned = _dragging;
    sim.reheat(0.5);
    _wake();
  }

  void _onDragUpdate(Offset delta) {
    final sim = _sim;
    final key = _dragging;
    if (sim == null || key == null) return;
    _dragDistance += delta.distance;
    sim.moveTo(key, sim.pos[key]! + delta);
    sim.reheat(0.3);
    _wake();
    setState(() {});
  }

  void _onDragEnd() {
    final sim = _sim;
    final key = _dragging;
    _dragging = null;
    if (sim == null || key == null) return;
    sim.pinned = null;
    // Barely moved: it was a tap.
    if (_dragDistance < 8) {
      setState(() => _selected = key);
      final node = widget.data.node(key);
      if (node != null) widget.onTapNode?.call(node);
    }
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, widget.height);
          final sim = _simFor(size);
          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _NodeDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_NodeDragRecognizer>(
                    () => _NodeDragRecognizer(hits: (p) => sim.hit(p) != null),
                    (r) => r
                      ..onStart = ((d) => _onDragStart(d.localPosition))
                      ..onUpdate = ((d) => _onDragUpdate(d.delta))
                      ..onEnd = ((_) => _onDragEnd())
                      ..onCancel = _onDragEnd,
                  ),
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (r) => r.onTap = () {
                      if (_selected != null) setState(() => _selected = null);
                    },
                  ),
            },
            child: _WebScene(
              data: widget.data,
              size: size,
              positions: sim.pos,
              diameters: sim.diameters,
              selected: _selected,
              grabbed: _dragging,
            ),
          );
        },
      ),
    );
  }
}

/// Claims the pointer at once when it lands on a person, so dragging them
/// doesn't scroll the page; touches on empty space are left to the page.
class _NodeDragRecognizer extends PanGestureRecognizer {
  final bool Function(Offset local) hits;

  _NodeDragRecognizer({required this.hits});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!hits(event.localPosition)) return;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// The web at rest, laid out by running the simulation to the end - for
/// the share image and the passport page.
class SwapWebCanvas extends StatelessWidget {
  final SwapWebData data;
  final Size size;
  final bool showNames;

  const SwapWebCanvas({
    super.key,
    required this.data,
    required this.size,
    this.showNames = true,
  });

  @override
  Widget build(BuildContext context) {
    final sim = WebSimulation(data, size)..settle();
    return _WebScene(
      data: data,
      size: size,
      positions: sim.pos,
      diameters: sim.diameters,
      showNames: showNames,
      showGrid: false,
    );
  }
}

/// Draws the web for given positions: dotted paper, links, then people.
class _WebScene extends StatelessWidget {
  final SwapWebData data;
  final Size size;
  final Map<String, Offset> positions;
  final Map<String, double> diameters;
  final String? selected;
  final String? grabbed;
  final bool showNames;
  final bool showGrid;

  const _WebScene({
    required this.data,
    required this.size,
    required this.positions,
    required this.diameters,
    this.selected,
    this.grabbed,
    this.showNames = true,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    // Focus: the selected person and their direct links stay bright.
    final focus = selected == null
        ? null
        : {
            selected!,
            for (final e in data.edges)
              if (e.touches(selected!)) e.other(selected!),
          };
    final maxEdge = data.edges.fold<int>(0, (m, e) => math.max(m, e.minutes));
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgePainter(
                data: data,
                positions: Map.of(positions),
                focus: selected,
                maxMinutes: maxEdge,
                outward: c.give,
                inward: c.get,
                mutual: c.success,
                muted: c.textMuted,
                grid: showGrid ? c.border : null,
              ),
            ),
          ),
          for (final n in data.nodes)
            if (positions[n.key] != null)
              _node(
                context,
                n,
                positions[n.key]!,
                diameters[n.key] ?? 40,
                dim: focus != null && !focus.contains(n.key),
              ),
        ],
      ),
    );
  }

  Widget _node(
    BuildContext context,
    WebNode n,
    Offset at,
    double d, {
    required bool dim,
  }) {
    final c = context.sw;
    final isMe = n.depth == 0;
    // Ring colour: how this person connects to the one before them.
    Color ring;
    if (isMe) {
      ring = c.win;
    } else {
      final link = data.edges
          .where((e) => e.touches(n.key) && e.touches(n.parent ?? ''))
          .firstOrNull;
      ring = link == null
          ? c.border
          : link.isMutual
          ? c.success
          : link.from == n.parent
          ? c.give
          : c.get;
    }
    final isSelected = n.key == selected;
    final lifted = n.key == grabbed;
    const labelWidth = 84.0;
    final label = isMe ? 'You' : n.name.split(' ').first;
    return Positioned(
      left: at.dx - labelWidth / 2,
      top: at.dy - d / 2,
      width: labelWidth,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: dim ? 0.3 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 160),
                scale: lifted ? 1.12 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.bg,
                    border: n.verified
                        ? null
                        : Border.all(
                            color: ring,
                            width: isMe || isSelected ? 3.2 : 2.2,
                          ),
                    boxShadow: [
                      if (isMe)
                        BoxShadow(
                          color: c.win.withValues(alpha: 0.55),
                          spreadRadius: 5,
                        ),
                      if (isSelected || lifted)
                        BoxShadow(
                          color: ring.withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  padding: EdgeInsets.all(n.verified ? 0 : 2),
                  child: SwapAvatar(
                    name: n.name.isEmpty ? '?' : n.name,
                    photoUrl: n.photoUrl.isEmpty ? null : n.photoUrl,
                    size: n.verified ? d : d - 4,
                    radius: d / 2,
                    color: isMe ? c.win : null,
                    verified: n.verified,
                  ),
                ),
              ),
              if (showNames)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: isMe ? 12 : 11,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final SwapWebData data;
  final Map<String, Offset> positions;
  final String? focus;
  final int maxMinutes;
  final Color outward;
  final Color inward;
  final Color mutual;
  final Color muted;
  final Color? grid;

  const _EdgePainter({
    required this.data,
    required this.positions,
    required this.focus,
    required this.maxMinutes,
    required this.outward,
    required this.inward,
    required this.mutual,
    required this.muted,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (grid != null) {
      final dot = Paint()..color = grid!.withValues(alpha: 0.9);
      for (double y = 11; y < size.height; y += 22) {
        for (double x = 11; x < size.width; x += 22) {
          canvas.drawCircle(Offset(x, y), 1, dot);
        }
      }
    }
    final depth = {for (final n in data.nodes) n.key: n.depth};
    for (final e in data.edges) {
      final a = positions[e.from];
      final b = positions[e.to];
      if (a == null || b == null) continue;
      final lit = focus == null || e.touches(focus!);
      // Mutual swaps are solid green. One-way lines are dashed with an arrow
      // from teacher to learner: orange when the skill went outward (the
      // teacher is nearer you), violet when it came in. Thicker = more time.
      final isOutward = (depth[e.from] ?? 0) <= (depth[e.to] ?? 0);
      var color = e.isMutual
          ? mutual
          : isOutward
          ? outward
          : inward;
      var width = maxMinutes <= 0
          ? 2.0
          : 1.5 + 5 * math.sqrt(e.minutes / maxMinutes).clamp(0.0, 1.0);
      if (!lit) {
        color = muted;
        width = math.min(width, 1.6);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: lit ? 0.85 : 0.28);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
      if (e.isMutual) {
        canvas.drawPath(path, paint);
        continue;
      }
      canvas.drawPath(_dashed(path, 7, 5), paint);
      _arrow(canvas, a, b, color.withValues(alpha: lit ? 0.95 : 0.3), width);
    }
  }

  Path _dashed(Path source, double dash, double gap) {
    final out = Path();
    for (final m in source.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(
          m.extractPath(d, math.min(d + dash, m.length)),
          Offset.zero,
        );
        d += dash + gap;
      }
    }
    return out;
  }

  /// A small filled arrowhead at the middle of a -> b, pointing at b.
  void _arrow(Canvas canvas, Offset a, Offset b, Color color, double width) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final dir = d / len;
    final normal = Offset(-dir.dy, dir.dx);
    final size = 6 + width;
    final tip = a + dir * (len / 2 + size / 2);
    final base = tip - dir * size;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + normal * size * 0.6).dx, (base + normal * size * 0.6).dy)
      ..lineTo((base - normal * size * 0.6).dx, (base - normal * size * 0.6).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

/// "3 h 20 m", "45 m".
String formatWebMinutes(int minutes) {
  if (minutes < 60) return '$minutes m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m m';
}

/// Legend under the map.
class SwapWebLegend extends StatelessWidget {
  const SwapWebLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    Widget item(Color color, String label, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 4,
          child: dashed
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(width: 5, height: 3, color: color),
                  ],
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.manrope(fontSize: 11, color: c.textMuted),
        ),
      ],
    );
    final hint = Text(
      'Drag people around · arrows point teacher → learner · thicker = more time',
      textAlign: TextAlign.center,
      style: AppTheme.label(
        fontSize: 10.5,
        color: c.textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
    return Column(
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            item(c.success, 'Mutual swap'),
            item(c.give, 'One-way: taught', dashed: true),
            item(c.get, 'One-way: learned', dashed: true),
          ],
        ),
        const SizedBox(height: 6),
        hint,
      ],
    );
  }
}
