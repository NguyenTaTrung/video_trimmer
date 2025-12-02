import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/src/trim_viewer/trim_editor_painter.dart';
import 'package:video_trimmer/src/trimmer.dart';
import 'package:video_trimmer/src/utils/duration_style.dart';

import '../../utils/editor_drag_type.dart';
import '../trim_area_properties.dart';
import '../trim_editor_properties.dart';
import 'fixed_thumbnail_viewer.dart';

class FixedTrimViewer extends StatefulWidget {
  final Trimmer trimmer;
  final double viewerWidth;
  final double viewerHeight;
  final Duration maxVideoLength;
  final bool showDuration;
  final TextStyle durationTextStyle;
  final DurationStyle durationStyle;
  final Function(double startValue)? onChangeStart;
  final Function(double endValue)? onChangeEnd;
  final Function(bool isPlaying)? onChangePlaybackState;
  final TrimEditorProperties editorProperties;
  final TrimAreaProperties areaProperties;
  final VoidCallback onThumbnailLoadingComplete;

  const FixedTrimViewer({
    super.key,
    required this.trimmer,
    required this.onThumbnailLoadingComplete,
    this.viewerWidth = 50.0 * 8,
    this.viewerHeight = 50,
    this.maxVideoLength = const Duration(milliseconds: 0),
    this.showDuration = true,
    this.durationTextStyle = const TextStyle(color: Colors.white),
    this.durationStyle = DurationStyle.FORMAT_HH_MM_SS,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangePlaybackState,
    this.editorProperties = const TrimEditorProperties(),
    this.areaProperties = const FixedTrimAreaProperties(),
  });

  @override
  State<FixedTrimViewer> createState() => _FixedTrimViewerState();
}

class _FixedTrimViewerState extends State<FixedTrimViewer>
    with TickerProviderStateMixin {
  final _trimmerAreaKey = GlobalKey();
  File? get _videoFile => widget.trimmer.currentVideoFile;

  double _videoStartPos = 0.0;
  double _videoEndPos = 0.0;

  Offset _startPos = const Offset(0, 0);
  Offset _endPos = const Offset(0, 0);

  double _startFraction = 0.0;
  double _endFraction = 1.0;

  int _videoDuration = 0;
  int _currentPosition = 0;

  double _thumbnailViewerW = 0.0;
  double _thumbnailViewerH = 0.0;

  int _numberOfThumbnails = 0;

  late double _startCircleSize;
  late double _endCircleSize;
  late double _borderRadius;

  double? fraction;
  double? maxLengthPixels;

  FixedThumbnailViewer? thumbnailWidget;

  Animation<double>? _scrubberAnimation;
  AnimationController? _animationController;
  late Tween<double> _linearTween;

  VideoPlayerController get videoPlayerController =>
      widget.trimmer.videoPlayerController!;

  EditorDragType _dragType = EditorDragType.left;
  bool _allowDrag = true;

  // --- THÊM: Padding để mở rộng vùng cảm ứng ---
  final double _touchPadding = 24.0;

  @override
  void initState() {
    super.initState();
    _startCircleSize = widget.editorProperties.circleSize;
    _endCircleSize = widget.editorProperties.circleSize;
    _borderRadius = widget.editorProperties.borderRadius;
    _thumbnailViewerH = widget.viewerHeight;
    log('thumbnailViewerW: $_thumbnailViewerW');
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final renderBox =
          _trimmerAreaKey.currentContext?.findRenderObject() as RenderBox?;
      final trimmerActualWidth = renderBox?.size.width;
      log('RENDER BOX: $trimmerActualWidth');
      if (trimmerActualWidth == null) return;
      _thumbnailViewerW = trimmerActualWidth;
      _initializeVideoController();
      videoPlayerController.seekTo(const Duration(milliseconds: 0));
      _numberOfThumbnails = trimmerActualWidth ~/ _thumbnailViewerH;
      log('numberOfThumbnails: $_numberOfThumbnails');
      log('thumbnailViewerW: $_thumbnailViewerW');
      setState(() {
        _thumbnailViewerW = _numberOfThumbnails * _thumbnailViewerH;

        final FixedThumbnailViewer thumbnailWidget = FixedThumbnailViewer(
          videoFile: _videoFile!,
          videoDuration: _videoDuration,
          fit: widget.areaProperties.thumbnailFit,
          thumbnailHeight: _thumbnailViewerH,
          numberOfThumbnails: _numberOfThumbnails,
          quality: widget.areaProperties.thumbnailQuality,
          onThumbnailLoadingComplete: widget.onThumbnailLoadingComplete,
        );
        this.thumbnailWidget = thumbnailWidget;
        Duration totalDuration = videoPlayerController.value.duration;

        if (widget.maxVideoLength > const Duration(milliseconds: 0) &&
            widget.maxVideoLength < totalDuration) {
          if (widget.maxVideoLength < totalDuration) {
            fraction = widget.maxVideoLength.inMilliseconds /
                totalDuration.inMilliseconds;

            maxLengthPixels = _thumbnailViewerW * fraction!;
          }
        } else {
          maxLengthPixels = _thumbnailViewerW;
        }

        _videoEndPos = fraction != null
            ? _videoDuration.toDouble() * fraction!
            : _videoDuration.toDouble();

        widget.onChangeEnd!(_videoEndPos);

        _endPos = Offset(
          maxLengthPixels != null ? maxLengthPixels! : _thumbnailViewerW,
          _thumbnailViewerH,
        );

        _linearTween = Tween(begin: _startPos.dx, end: _endPos.dx);
        _animationController = AnimationController(
          vsync: this,
          duration:
              Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt()),
        );

        _scrubberAnimation = _linearTween.animate(_animationController!)
          ..addListener(() {
            setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _animationController!.stop();
            }
          });
      });
    });
  }

  Future<void> _initializeVideoController() async {
    if (_videoFile != null) {
      videoPlayerController.addListener(() {
        final bool isPlaying = videoPlayerController.value.isPlaying;

        if (isPlaying) {
          widget.onChangePlaybackState!(true);
          setState(() {
            _currentPosition =
                videoPlayerController.value.position.inMilliseconds;

            if (_currentPosition > _videoEndPos.toInt()) {
              videoPlayerController.pause();
              widget.onChangePlaybackState!(false);
              _animationController!.stop();
            } else {
              if (!_animationController!.isAnimating) {
                widget.onChangePlaybackState!(true);
                _animationController!.forward();
              }
            }
          });
        } else {
          if (videoPlayerController.value.isInitialized) {
            if (_animationController != null) {
              if ((_scrubberAnimation?.value ?? 0).toInt() ==
                  (_endPos.dx).toInt()) {
                _animationController!.reset();
              }
              _animationController!.stop();
              widget.onChangePlaybackState!(false);
            }
          }
        }
      });

      videoPlayerController.setVolume(1.0);
      _videoDuration = videoPlayerController.value.duration.inMilliseconds;
    }
  }

  void _onDragStart(DragStartDetails details) {
    debugPrint("_onDragStart");
    
    // --- SỬA LOGIC DRAG ---
    // Tính toạ độ thực bằng cách trừ đi padding (vì ta đã thêm padding ở UI)
    // Nếu không trừ, toạ độ chạm sẽ bị lệch sang phải 24px
    final touchDx = details.localPosition.dx - _touchPadding;
    
    final startDifference = _startPos.dx - touchDx;
    final endDifference = _endPos.dx - touchDx;

    // Check vùng chạm (Hit Test)
    if (startDifference <= widget.editorProperties.sideTapSize &&
        endDifference >= -widget.editorProperties.sideTapSize) {
      _allowDrag = true;
    } else {
      debugPrint("Dragging is outside of frame, ignoring gesture...");
      _allowDrag = false;
      return;
    }

    if (touchDx <= _startPos.dx + widget.editorProperties.sideTapSize) {
      _dragType = EditorDragType.left;
    } else if (touchDx <= _endPos.dx - widget.editorProperties.sideTapSize) {
      _dragType = EditorDragType.center;
    } else {
      _dragType = EditorDragType.right;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_allowDrag) return;

    if (_dragType == EditorDragType.left) {
      _startCircleSize = widget.editorProperties.circleSizeOnDrag;
      if ((_startPos.dx + details.delta.dx >= 0) &&
          (_startPos.dx + details.delta.dx <= _endPos.dx) &&
          !(_endPos.dx - _startPos.dx - details.delta.dx > maxLengthPixels!)) {
        _startPos += details.delta;
        _onStartDragged();
      }
    } else if (_dragType == EditorDragType.center) {
      _startCircleSize = widget.editorProperties.circleSizeOnDrag;
      _endCircleSize = widget.editorProperties.circleSizeOnDrag;
      if ((_startPos.dx + details.delta.dx >= 0) &&
          (_endPos.dx + details.delta.dx <= _thumbnailViewerW)) {
        _startPos += details.delta;
        _endPos += details.delta;
        _onStartDragged();
        _onEndDragged();
      }
    } else {
      _endCircleSize = widget.editorProperties.circleSizeOnDrag;
      if ((_endPos.dx + details.delta.dx <= _thumbnailViewerW) &&
          (_endPos.dx + details.delta.dx >= _startPos.dx) &&
          !(_endPos.dx - _startPos.dx + details.delta.dx > maxLengthPixels!)) {
        _endPos += details.delta;
        _onEndDragged();
      }
    }
    setState(() {});
  }

  void _onStartDragged() {
    _startFraction = (_startPos.dx / _thumbnailViewerW);
    _videoStartPos = _videoDuration * _startFraction;
    widget.onChangeStart!(_videoStartPos);
    _linearTween.begin = _startPos.dx;
    _animationController!.duration =
        Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
    _animationController!.reset();
  }

  void _onEndDragged() {
    _endFraction = _endPos.dx / _thumbnailViewerW;
    _videoEndPos = _videoDuration * _endFraction;
    widget.onChangeEnd!(_videoEndPos);
    _linearTween.end = _endPos.dx;
    _animationController!.duration =
        Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
    _animationController!.reset();
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _startCircleSize = widget.editorProperties.circleSize;
      _endCircleSize = widget.editorProperties.circleSize;
      if (_dragType == EditorDragType.right) {
        videoPlayerController
            .seekTo(Duration(milliseconds: _videoEndPos.toInt()));
      } else {
        videoPlayerController
            .seekTo(Duration(milliseconds: _videoStartPos.toInt()));
      }
    });
  }

  @override
  void dispose() {
    videoPlayerController.pause();
    widget.onChangePlaybackState!(false);
    if (_videoFile != null) {
      videoPlayerController.setVolume(0.0);
      videoPlayerController.dispose();
      widget.onChangePlaybackState!(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double borderWidth = widget.editorProperties.borderWidth;

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      behavior: HitTestBehavior.opaque, // QUAN TRỌNG: Bắt chạm cả ở vùng trong suốt
      child: Container(
        // --- SỬA UI: Thêm padding để mở rộng vùng chạm ---
        // Vùng này trong suốt nhưng GestureDetector vẫn bắt được nhờ HitTestBehavior.opaque
        padding: EdgeInsets.symmetric(horizontal: _touchPadding),
        color: Colors.transparent,
        
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            widget.showDuration
                ? SizedBox(
                    width: _thumbnailViewerW,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: <Widget>[
                          Text(
                              Duration(milliseconds: _videoStartPos.toInt())
                                  .format(widget.durationStyle),
                              style: widget.durationTextStyle),
                          videoPlayerController.value.isPlaying
                              ? Text(
                                  Duration(milliseconds: _currentPosition.toInt())
                                      .format(widget.durationStyle),
                                  style: widget.durationTextStyle)
                              : Container(),
                          Text(
                              Duration(milliseconds: _videoEndPos.toInt())
                                  .format(widget.durationStyle),
                              style: widget.durationTextStyle),
                        ],
                      ),
                    ),
                  )
                : Container(),
            SizedBox(
              height: _thumbnailViewerH,
              width: _thumbnailViewerW == 0.0
                  ? widget.viewerWidth
                  : _thumbnailViewerW,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    key: _trimmerAreaKey,
                    color: Colors.grey[900],
                    height: _thumbnailViewerH,
                    width: _thumbnailViewerW == 0.0
                        ? widget.viewerWidth
                        : _thumbnailViewerW,
                    child: thumbnailWidget ?? Container(),
                  ),
                  if (widget.areaProperties.blurEdges) ...[
                    Positioned(
                      left: 0,
                      width: _startPos.dx,
                      top: 0,
                      bottom: 0,
                      child: Container(color: widget.areaProperties.blurColor),
                    ),
                    Positioned(
                      left: _endPos.dx,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(color: widget.areaProperties.blurColor),
                    ),
                  ],
                  CustomPaint(
                    foregroundPainter: TrimEditorPainter(
                      startPos: _startPos,
                      endPos: _endPos,
                      scrubberAnimationDx: _scrubberAnimation?.value ?? 0,
                      startCircleSize: _startCircleSize,
                      endCircleSize: _endCircleSize,
                      borderRadius: _borderRadius,
                      borderWidth: widget.editorProperties.borderWidth,
                      scrubberWidth: widget.editorProperties.scrubberWidth,
                      circlePaintColor: widget.editorProperties.circlePaintColor,
                      borderPaintColor: widget.editorProperties.borderPaintColor,
                      scrubberPaintColor:
                          widget.editorProperties.scrubberPaintColor,
                    ),
                  ),
                  if (widget.areaProperties.startIcon != null)
                    Positioned(
                      left: _startPos.dx - 16,
                      top: - borderWidth / 2,
                      bottom: - borderWidth / 2,
                      child: widget.areaProperties.startIcon!,
                    ),
                  if (widget.areaProperties.endIcon != null)
                    Positioned(
                      left: _endPos.dx,
                      top: - borderWidth / 2,
                      bottom: - borderWidth / 2,
                      child: widget.areaProperties.endIcon!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
