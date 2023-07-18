import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_card_swiper/src/card_swiper_controller.dart';
import 'package:flutter_card_swiper/src/enums.dart';
import 'package:flutter_card_swiper/src/typedefs.dart';

class CardSwiper extends StatefulWidget {
  /// list of widgets for the swiper
  final List<Widget?> cards;

  /// controller to trigger actions
  final CardSwiperController? controller;

  /// duration of every animation
  final Duration duration;

  /// padding of the swiper
  final EdgeInsetsGeometry padding;

  /// maximum angle the card reaches while swiping
  final double maxAngle;

  /// threshold from which the card is swiped away
  final int threshold;

  /// index of the first item when we create swiper
  final int initialIndex;

  /// scale of the card that is behind the front card
  final double scale;

  /// set to true if swiping should be disabled, exception: triggered from the outside
  final bool isDisabled;

  /// function that gets called with the new index and detected swipe direction when the user swiped or swipe is triggered by controller
  final CardSwiperOnSwipe? onSwipe;

  /// function that gets called when there is no widget left to be swiped away
  final CardSwiperOnEnd? onEnd;

  /// function that gets triggered when the swiper is disabled
  final CardSwiperOnTapDisabled? onTapDisabled;

  /// direction in which the card gets swiped when triggered by controller, default set to right
  final CardSwiperDirection direction;

  /// callback that will be invoked before run swipe animation. Invoke even if
  /// current swipe direction currently disabled and in contains [disabledDirections]
  final ValueChanged<CardSwiperDirection>? beforeSwipe;

  /// list of directions that will be disabled to swipe manually or with controller
  final List<CardSwiperDirection> disabledDirections;

  /// notifier that would be fired when user drag the item
  final ValueChanged<Offset>? onDrag;

  final ValueChanged<int>? onItemIndexChange;

  const CardSwiper({
    Key? key,
    required this.cards,
    this.maxAngle = 30,
    this.threshold = 50,
    this.initialIndex = 0,
    this.scale = 0.9,
    this.isDisabled = false,
    this.disabledDirections = const [],
    this.direction = CardSwiperDirection.right,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
    this.duration = const Duration(milliseconds: 200),
    this.controller,
    this.onTapDisabled,
    this.onSwipe,
    this.onEnd,
    this.beforeSwipe,
    this.onDrag,
    this.onItemIndexChange,
  })  : assert(
          maxAngle >= 0 && maxAngle <= 360,
          'maxAngle must be between 0 and 360',
        ),
        assert(
          threshold >= 1 && threshold <= 100,
          'threshold must be between 1 and 100',
        ),
        assert(
          direction != CardSwiperDirection.none,
          'direction must not be none',
        ),
        assert(
          scale >= 0 && scale <= 1,
          'scale must be between 0 and 1',
        ),
        super(key: key);

  @override
  State createState() => _CardSwiperState();
}

class _CardSwiperState extends State<CardSwiper> with TickerProviderStateMixin {
  double _left = 0;
  double _top = 0;
  double _total = 0;
  double _angle = 0;
  late double _scale = widget.scale;
  double _difference = 40;

  int _currentIndex = 0;

  SwipeType _swipeType = SwipeType.none;
  bool _tapOnTop = false;

  late AnimationController _animationController;
  late AnimationController _returnController;
  late Animation<double> _returnAnimation;
  late Animation<double> _leftAnimation;
  late Animation<double> _topAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _differenceAnimation;

  CardSwiperDirection detectedDirection = CardSwiperDirection.none;

  double get _maxAngle => widget.maxAngle * (pi / 180);

  bool get _isLastCard => _currentIndex == widget.cards.length - 1;

  int get _nextCardIndex => _isLastCard ? 0 : _currentIndex + 1;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;

    widget.controller?.addListener(_controllerListener);

    _animationController = AnimationController(
      duration: widget.duration,
      vsync: this,
    )
      ..addListener(_animationListener)
      ..addStatusListener(_animationStatusListener);

    _returnController = AnimationController(
      duration: widget.duration,
      vsync: this,
    )
      ..addListener(_returnListener);
    _returnAnimation = Tween<double>(
      begin: widget.threshold.toDouble(),
      end: 0,
    ).animate(_returnController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _returnController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Padding(
          padding: widget.padding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  _backItem(constraints),
                  _frontItem(constraints),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _frontItem(BoxConstraints constraints) {
    return Positioned(
      left: _left,
      top: _top,
      child: GestureDetector(
        child: Transform.rotate(
          angle: _angle,
          child: ConstrainedBox(
            constraints: constraints,
            child: widget.cards[_currentIndex],
          ),
        ),
        onTap: () {
          if (widget.isDisabled) {
            widget.onTapDisabled?.call();
          }
        },
        onPanStart: (tapInfo) {
          if (!widget.isDisabled) {
            final renderBox = context.findRenderObject()! as RenderBox;
            final position = renderBox.globalToLocal(tapInfo.globalPosition);

            if (position.dy < renderBox.size.height / 2) _tapOnTop = true;
          }
        },
        onPanUpdate: (tapInfo) {
          if (widget.isDisabled) {
            return;
          }

          setState(() {
            _left += tapInfo.delta.dx;
            _top += tapInfo.delta.dy;
            _total = _left + _top;
            _calculateAngle();
            _calculateScale();
            _calculateDifference();
          });

          final offset = Offset(_left, _top);
          widget.onDrag?.call(offset);
        },
        onPanEnd: (tapInfo) {
          if (!widget.isDisabled) {
            _tapOnTop = false;
            _onEndAnimation();
            _animationController.forward();
          }
        },
      ),
    );
  }

  Widget _backItem(BoxConstraints constraints) {
    if(_currentIndex > widget.cards.length - 1) {
      if(widget.cards.isNotEmpty) {
        _currentIndex = widget.cards.length - 1;
      } else {
        _currentIndex = 0;
      }
      widget.onItemIndexChange?.call(_currentIndex);
    }

    if(_currentIndex < 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: _difference,
      left: 0,
      child: Transform.scale(
        scale: _scale,
        child: ConstrainedBox(
          constraints: constraints,
          child: widget.cards[_nextCardIndex],
        ),
      ),
    );
  }

  //swipe widget from the outside
  void _controllerListener() {
    switch (widget.controller!.state) {
      case CardSwiperState.swipe:
        _swipe(context, widget.direction);
        break;
      case CardSwiperState.swipeLeft:
        _swipe(context, CardSwiperDirection.left);
        break;
      case CardSwiperState.swipeRight:
        _swipe(context, CardSwiperDirection.right);
        break;
      case CardSwiperState.swipeTop:
        _swipe(context, CardSwiperDirection.top);
        break;
      case CardSwiperState.swipeBottom:
        _swipe(context, CardSwiperDirection.bottom);
        break;
      default:
        break;
    }
  }

  //when value of controller changes
  void _animationListener() {
    if (_animationController.status == AnimationStatus.forward) {
      setState(() {
        _left = _leftAnimation.value;
        _top = _topAnimation.value;
        _scale = _scaleAnimation.value;
        _difference = _differenceAnimation.value;
      });
    }
    if (_animationController.status == AnimationStatus.forward ||
        _animationController.status == AnimationStatus.reverse) {
      final offset = Offset(
        min(_leftAnimation.value, widget.threshold.toDouble()),
        min(_topAnimation.value, widget.threshold.toDouble()),
      );

      widget.onDrag?.call(offset);
    }
  }

  //when the status of animation changes
  void _animationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        if (_swipeType == SwipeType.swipe) {
          widget.onSwipe?.call(_currentIndex, detectedDirection);

          if (_isLastCard) {
            widget.onEnd?.call();
            _currentIndex = 0;
          } else {
            _currentIndex++;
          }
          widget.onItemIndexChange?.call(_currentIndex);
        }
        _animationController.reset();
        _left = 0;
        _top = 0;
        _total = 0;
        _angle = 0;
        _scale = widget.scale;
        _difference = 40;
        _swipeType = SwipeType.none;
      });
    }
  }

  void _calculateAngle() {
    if (_angle <= _maxAngle && _angle >= -_maxAngle) {
      _angle = (_maxAngle / 100) * (_left / 10);
      if (_tapOnTop) _angle *= -1;
    }
  }

  void _calculateScale() {
    if (_scale <= 1.0 && _scale >= widget.scale) {
      _scale = (_total > 0)
          ? widget.scale + (_total / 5000)
          : widget.scale + -1 * (_total / 5000);
    }
  }

  void _calculateDifference() {
    if (_difference >= 0 && _difference <= _difference) {
      _difference = (_total > 0) ? 40 - (_total / 10) : 40 + (_total / 10);
    }
  }

  void _onEndAnimation() {
    if (_left < -widget.threshold || _left > widget.threshold) {
      _swipeHorizontal(context);
    } else if (_top < -widget.threshold || _top > widget.threshold) {
      _swipeVertical(context);
    } else {
      _goBack(context);
    }
  }

  void _swipe(BuildContext context, CardSwiperDirection direction) {
    if (widget.cards.isEmpty) return;

    switch (direction) {
      case CardSwiperDirection.left:
        if (widget.disabledDirections.contains(CardSwiperDirection.left)) {
          _goBack(context);
        } else {
          _left = -1;
          _swipeHorizontal(context);
        }
        break;
      case CardSwiperDirection.right:
        if (widget.disabledDirections.contains(CardSwiperDirection.right)) {
          _goBack(context);
        } else {
          _left = widget.threshold + 1;
          _swipeHorizontal(context);
        }
        break;
      case CardSwiperDirection.top:
        if (widget.disabledDirections.contains(CardSwiperDirection.top)) {
          _goBack(context);
        } else {
          _top = -1;
          _swipeVertical(context);
        }
        break;
      case CardSwiperDirection.bottom:
        if (widget.disabledDirections.contains(CardSwiperDirection.bottom)) {
          _goBack(context);
        } else {
          _top = widget.threshold + 1;
          _swipeVertical(context);
        }
        break;
      default:
        break;
    }
    _animationController.forward();
  }

  //moves the card away to the left or right
  void _swipeHorizontal(BuildContext context) {
    if (_left > widget.threshold ||
        _left == 0 && widget.direction == CardSwiperDirection.right) {
      detectedDirection = CardSwiperDirection.right;
    } else {
      detectedDirection = CardSwiperDirection.left;
    }

    widget.beforeSwipe?.call(detectedDirection);

    if (widget.disabledDirections.contains(detectedDirection)) {
      _goBack(context);
      return;
    }

    _leftAnimation = Tween<double>(
      begin: _left,
      end: (_left == 0 && widget.direction == CardSwiperDirection.right) ||
              _left > widget.threshold
          ? MediaQuery.of(context).size.width
          : -MediaQuery.of(context).size.width,
    ).animate(_animationController);
    _topAnimation = Tween<double>(
      begin: _top,
      end: _top + _top,
    ).animate(_animationController);
    _scaleAnimation = Tween<double>(
      begin: _scale,
      end: 1.0,
    ).animate(_animationController);
    _differenceAnimation = Tween<double>(
      begin: _difference,
      end: 0,
    ).animate(_animationController);

    _swipeType = SwipeType.swipe;
  }

  //moves the card away to the top or bottom
  void _swipeVertical(BuildContext context) {
    if (_top > widget.threshold ||
        _top == 0 && widget.direction == CardSwiperDirection.bottom) {
      detectedDirection = CardSwiperDirection.bottom;
    } else {
      detectedDirection = CardSwiperDirection.top;
    }

    widget.beforeSwipe?.call(detectedDirection);

    if (widget.disabledDirections.contains(detectedDirection)) {
      _goBack(context);
      return;
    }

    _leftAnimation = Tween<double>(
      begin: _left,
      end: _left + _left,
    ).animate(_animationController);
    _topAnimation = Tween<double>(
      begin: _top,
      end: (_top == 0 && widget.direction == CardSwiperDirection.bottom) ||
              _top > widget.threshold
          ? MediaQuery.of(context).size.height
          : -MediaQuery.of(context).size.height,
    ).animate(_animationController);
    _scaleAnimation = Tween<double>(
      begin: _scale,
      end: 1.0,
    ).animate(_animationController);
    _differenceAnimation = Tween<double>(
      begin: _difference,
      end: 0,
    ).animate(_animationController);

    _swipeType = SwipeType.swipe;
  }

  //moves the card back to starting position
  void _goBack(BuildContext context) {
    _leftAnimation = Tween<double>(
      begin: _left,
      end: 0,
    ).animate(_animationController);
    _topAnimation = Tween<double>(
      begin: _top,
      end: 0,
    ).animate(_animationController);
    _scaleAnimation = Tween<double>(
      begin: _scale,
      end: widget.scale,
    ).animate(_animationController);
    _differenceAnimation = Tween<double>(
      begin: _difference,
      end: 40,
    ).animate(_animationController);

    _swipeType = SwipeType.back;
  }

  void _returnListener() {
    final value = _returnAnimation.value;
    if(value != widget.threshold.toDouble()) {
      final offset = Offset(value, value);
      widget.onDrag?.call(offset);
    }

    final status = _returnController.status;
    if (status == AnimationStatus.completed) {
      _returnController.value = 0;
    }
  }
}
