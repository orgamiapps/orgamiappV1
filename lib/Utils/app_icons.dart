class AppIcons {
  static const String _basePath = "images/svg/";

  static String _svgPath(String name) {
    return "$_basePath$name.svg";
  }

  static String location = _svgPath("location");
}
