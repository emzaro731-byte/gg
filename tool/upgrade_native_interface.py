from pathlib import Path

p = Path('lib/main.dart')
s = p.read_text()

# Refine the global Flutter Material 3 design system without changing navigation,
# Supabase, calls, notifications, or existing page implementations.
s = s.replace(
"""    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF08070C) : const Color(0xFFF7F5FB),
      visualDensity: VisualDensity.standard,""",
"""    final textTheme = Typography.material2021(platform: TargetPlatform.android).black.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF08070C) : const Color(0xFFF7F5FB),
      visualDensity: VisualDensity.adaptivePlatformDensity,""",
1)

s = s.replace(
"""      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,""",
"""      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 68,
        titleSpacing: 20,""",
1)

s = s.replace(
"""      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,""",
"""      navigationBarTheme: NavigationBarThemeData(
        height: 78,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),""",
1)

s = s.replace(
"""      inputDecorationTheme: InputDecorationTheme(
        filled: true,""",
"""      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: false,""",
1)

# Give the primary action a more intentional, native Material shape.
s = s.replace(
"""      cardTheme: CardThemeData(
        elevation: 0,""",
"""      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,""",
1)

# Make the home background and bottom navigation feel layered rather than web-like.
s = s.replace(
"""    return Scaffold(
      extendBody: true,
      appBar: AppBar(""",
"""    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(""",
1)

p.write_text(s)
print('Applied upgraded native Flutter Material interface.')
