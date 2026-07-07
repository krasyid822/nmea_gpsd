class NmeaGenerator {
  /// Formats decimal degrees to NMEA DDMM.MMMMM format
  static String _formatLatitude(double lat) {
    final absLat = lat.abs();
    final degrees = absLat.toInt();
    final minutes = (absLat - degrees) * 60.0;
    
    final degStr = degrees.toString().padLeft(2, '0');
    final minStr = minutes.toStringAsFixed(5).padLeft(8, '0'); // MM.MMMMM
    
    return '$degStr$minStr';
  }

  /// Formats decimal degrees to NMEA DDDMM.MMMMM format
  static String _formatLongitude(double lon) {
    final absLon = lon.abs();
    final degrees = absLon.toInt();
    final minutes = (absLon - degrees) * 60.0;
    
    final degStr = degrees.toString().padLeft(3, '0');
    final minStr = minutes.toStringAsFixed(5).padLeft(8, '0'); // MM.MMMMM
    
    return '$degStr$minStr';
  }

  /// Computes the XOR checksum of an NMEA sentence
  static String _computeChecksum(String sentence) {
    int checksum = 0;
    // Skip the '$' at the beginning
    for (int i = 1; i < sentence.length; i++) {
      checksum ^= sentence.codeUnitAt(i);
    }
    return checksum.toRadixString(16).toUpperCase().padLeft(2, '0');
  }

  /// Generates a $GPRMC sentence
  static String generateRmc({
    required double latitude,
    required double longitude,
    required double speedKph, // Speed in km/h
    required double heading, // Heading in degrees
    required DateTime time,
  }) {
    // Speed over ground: convert km/h to knots (1 knot = 1.852 km/h)
    final speedKnots = speedKph / 1.852;
    
    final utcTime = time.toUtc();
    final timeStr = '${utcTime.hour.toString().padLeft(2, '0')}'
        '${utcTime.minute.toString().padLeft(2, '0')}'
        '${utcTime.second.toString().padLeft(2, '0')}.00';
        
    final dateStr = '${utcTime.day.toString().padLeft(2, '0')}'
        '${utcTime.month.toString().padLeft(2, '0')}'
        '${(utcTime.year % 100).toString().padLeft(2, '0')}';

    final latVal = _formatLatitude(latitude);
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lonVal = _formatLongitude(longitude);
    final lonDir = longitude >= 0 ? 'E' : 'W';

    final speedStr = speedKnots.toStringAsFixed(3);
    final headingStr = heading.toStringAsFixed(2);

    final sentenceWithoutChecksum = 'GPRMC,$timeStr,A,$latVal,$latDir,$lonVal,$lonDir,$speedStr,$headingStr,$dateStr,,,A';
    final checksum = _computeChecksum('\$$sentenceWithoutChecksum');
    
    return '\$$sentenceWithoutChecksum*$checksum';
  }

  /// Generates a $GPGGA sentence
  static String generateGga({
    required double latitude,
    required double longitude,
    required double altitude, // Altitude in meters
    required double accuracy, // Horizontal accuracy
    required DateTime time,
  }) {
    final utcTime = time.toUtc();
    final timeStr = '${utcTime.hour.toString().padLeft(2, '0')}'
        '${utcTime.minute.toString().padLeft(2, '0')}'
        '${utcTime.second.toString().padLeft(2, '0')}.00';

    final latVal = _formatLatitude(latitude);
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lonVal = _formatLongitude(longitude);
    final lonDir = longitude >= 0 ? 'E' : 'W';

    // GPS Quality: 1 = Fix valid, 0 = Invalid
    const gpsQuality = '1';
    // Simulated satellite count: 12 is high accuracy
    const satellites = '12';
    
    // HDOP can be estimated using accuracy/5.0 or 1.0
    final hdop = (accuracy / 5.0).clamp(0.5, 99.0).toStringAsFixed(1);
    final altStr = altitude.toStringAsFixed(2);

    final sentenceWithoutChecksum = 'GPGGA,$timeStr,$latVal,$latDir,$lonVal,$lonDir,$gpsQuality,$satellites,$hdop,$altStr,M,0.0,M,,';
    final checksum = _computeChecksum('\$$sentenceWithoutChecksum');
    
    return '\$$sentenceWithoutChecksum*$checksum';
  }
}
