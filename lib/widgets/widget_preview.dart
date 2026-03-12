import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/personalization_provider.dart';

class WidgetPreview extends StatefulWidget {
  final bool isDark;
  final int transparency;

  const WidgetPreview({
    super.key,
    required this.isDark,
    required this.transparency,
  });

  @override
  State<WidgetPreview> createState() => _WidgetPreviewState();
}

class _WidgetPreviewState extends State<WidgetPreview> {
  static const platform = MethodChannel('com.gargun.btktimetable/widget');
  Uint8List? _wallpaperBytes;
  bool _isLoadingWallpaper = true;

  @override
  void initState() {
    super.initState();
    _loadWallpaper();
  }

  Future<void> _loadWallpaper() async {
    try {
      final bytes = await platform.invokeMethod('getWallpaper');
      if (mounted) {
        setState(() {
          _wallpaperBytes = bytes;
          _isLoadingWallpaper = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading wallpaper: $e');
      if (mounted) {
        setState(() {
          _isLoadingWallpaper = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final personalizationProvider = context.watch<PersonalizationProvider>();
    final widgetColor = personalizationProvider.settings.seedColor;

    // Calculate background color with transparency
    final baseColor = widget.isDark ? Colors.black : Colors.white;
    final opacity = (100 - widget.transparency) / 100.0;
    final backgroundColor =
        baseColor.withValues(alpha: opacity.clamp(0.0, 1.0));

    final textColor = widget.isDark ? Colors.white : Colors.black;
    final secondaryTextColor = widget.isDark ? Colors.white70 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8.0),
          child: Text(
            'Предпросмотр виджетов',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          height: 300, // Fixed height for the preview area
          decoration: BoxDecoration(
            image: _wallpaperBytes != null
                ? DecorationImage(
                    image: MemoryImage(_wallpaperBytes!),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.2), BlendMode.darken),
                  )
                : null,
            gradient: _wallpaperBytes == null
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blueGrey.shade800,
                      Colors.blueGrey.shade600,
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[300], // Fallback
          ),
          child: _isLoadingWallpaper
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Main Schedule Widget Mock
                      _buildWidgetContainer(
                        backgroundColor: backgroundColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(textColor, 'Расписание', '483'),
                            const SizedBox(height: 8),
                            _buildLessonItem(
                              '1. Веб прогр на стороне сервера',
                              '08:30 - 10:05',
                              'О47',
                              textColor,
                              secondaryTextColor,
                              false,
                              widgetColor,
                            ),
                            _buildLessonItem(
                              '2. Компьютерные сети',
                              '10:15 - 11:50',
                              'О47',
                              textColor,
                              secondaryTextColor,
                              true, // Active
                              widgetColor,
                            ),
                            _buildLessonItem(
                              '3. Физкультура',
                              '12:10 - 13:45',
                              'Спортзал',
                              textColor,
                              secondaryTextColor,
                              false,
                              widgetColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Bell Schedule Widget Mock
                      _buildWidgetContainer(
                        backgroundColor: backgroundColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(textColor, 'Звонки', 'Пн, Ср, Пт'),
                            const SizedBox(height: 8),
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              childAspectRatio: 2.5,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                              children: [
                                _buildBellItem(
                                    '1 пара',
                                    '08:30 - 09:15',
                                    textColor,
                                    secondaryTextColor,
                                    false,
                                    widgetColor),
                                _buildBellItem('', '09:20 - 10:05', textColor,
                                    secondaryTextColor, false, widgetColor),
                                _buildBellItem(
                                    '2 пара',
                                    '10:15 - 11:00',
                                    textColor,
                                    secondaryTextColor,
                                    true,
                                    widgetColor),
                                _buildBellItem('', '11:05 - 11:50', textColor,
                                    secondaryTextColor, true, widgetColor),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWidgetContainer(
      {required Color backgroundColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeader(Color textColor, String title, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLessonItem(
    String title,
    String time,
    String room,
    Color textColor,
    Color secondaryColor,
    bool isActive,
    Color highlightColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: isActive
          ? BoxDecoration(
              color: highlightColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isActive ? Colors.black : textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  time,
                  style: TextStyle(
                    color: isActive ? Colors.black : secondaryColor,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            room,
            style: TextStyle(
              color: isActive ? Colors.black : secondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBellItem(
    String title,
    String time,
    Color textColor,
    Color secondaryColor,
    bool isActive,
    Color highlightColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: isActive
          ? BoxDecoration(
              color: highlightColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                color: isActive ? Colors.black : secondaryColor,
                fontSize: 10,
              ),
            ),
          Text(
            time,
            style: TextStyle(
              color: isActive ? Colors.black : textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
