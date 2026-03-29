import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class ResponsiveScale {
  static const double _baseWidth = 390;
  static const double _baseHeight = 844;

  final BuildContext context;

  const ResponsiveScale(this.context);

  Size get _size => MediaQuery.sizeOf(context);

  double get _widthScale => (_size.width / _baseWidth).clamp(0.82, 1.25);

  double get _heightScale => (_size.height / _baseHeight).clamp(0.82, 1.25);

  double get _uniformScale => math.min(_widthScale, _heightScale);

  double scale(double value) => value * _uniformScale;

  double width(double value) => value * _widthScale;

  double height(double value) => value * _heightScale;

  double font(double value) => value * _uniformScale;

  EdgeInsets insetsAll(double value) => EdgeInsets.all(scale(value));

  EdgeInsets insetsSymmetric({double horizontal = 0, double vertical = 0}) {
    return EdgeInsets.symmetric(
      horizontal: width(horizontal),
      vertical: height(vertical),
    );
  }
}

extension ResponsiveContext on BuildContext {
  ResponsiveScale get rs => ResponsiveScale(this);
}
