import 'package:nipaplay/models/watch_history_model.dart';

// Jellyfin媒体库
class JellyfinLibrary {
  final String id;
  final String name;
  final String? type;
  final String? imageTagsPrimary;
  final int? totalItems;
  
  JellyfinLibrary({
    required this.id,
    required this.name,
    this.type,
    this.imageTagsPrimary,
    this.totalItems,
  });
  
  factory JellyfinLibrary.fromJson(Map<String, dynamic> json) {
    return JellyfinLibrary(
      id: json['Id'],
      name: json['Name'],
      type: json['CollectionType'],
      imageTagsPrimary: json['ImageTags']?['Primary'],
      totalItems: json['ChildCount'], // Reverted to use ChildCount
    );
  }
}

// Jellyfin媒体项目（电视剧、电影等）
class JellyfinMediaItem {
  final String id;
  final String name;
  final String? overview;
  final String? originalTitle;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final int? productionYear;
  final DateTime dateAdded;
  final String? premiereDate;
  final String? communityRating;
  
  JellyfinMediaItem({
    required this.id,
    required this.name,
    this.overview,
    this.originalTitle,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.productionYear,
    required this.dateAdded,
    this.premiereDate,
    this.communityRating,
  });
  
  factory JellyfinMediaItem.fromJson(Map<String, dynamic> json) {
    return JellyfinMediaItem(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      originalTitle: json['OriginalTitle'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      imageBackdropTag: json['BackdropImageTags']?.isNotEmpty == true ? json['BackdropImageTags'][0] : null,
      productionYear: json['ProductionYear'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      communityRating: json['CommunityRating']?.toString(),
    );
  }
  
  // 将JellyfinMediaItem转换为WatchHistoryItem，用于与现有系统兼容
  WatchHistoryItem toWatchHistoryItem({int? lastPosition = 0, int? duration = 0}) {
    return WatchHistoryItem(
      filePath: 'jellyfin://$id', // 使用jellyfin://协议来区分本地文件
      animeName: name,
      episodeTitle: null,
      watchProgress: 0.0,
      lastPosition: lastPosition ?? 0,
      duration: duration ?? 0,
      lastWatchTime: DateTime.now(),
      animeId: null, // Jellyfin不使用animeId系统，但我们可以在应用内部使用另一种映射
      isFromScan: false,
    );
  }
}

// Jellyfin媒体详情（包含更多元数据）
class JellyfinMediaItemDetail {
  final String id;
  final String name;
  final String? overview;
  final String? originalTitle;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final int? productionYear;
  final DateTime dateAdded;
  final String? premiereDate;
  final String? communityRating;
  final List<String> genres;
  final String? officialRating;
  final List<JellyfinPerson> cast;
  final List<JellyfinPerson> directors;
  final int? runTimeTicks;
  final String? seriesStudio;
  final String type; // 新增type字段
  
  JellyfinMediaItemDetail({
    required this.id,
    required this.name,
    this.overview,
    this.originalTitle,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.productionYear,
    required this.dateAdded,
    this.premiereDate,
    this.communityRating,
    required this.genres,
    this.officialRating,
    required this.cast,
    required this.directors,
    this.runTimeTicks,
    this.seriesStudio,
    required this.type, // 新增type字段
  });
  
  factory JellyfinMediaItemDetail.fromJson(Map<String, dynamic> json) {
    // 解析演员信息
    List<JellyfinPerson> cast = [];
    if (json['People'] != null) {
      cast = (json['People'] as List)
          .where((person) => person['Type'] == 'Actor')
          .map((e) => JellyfinPerson.fromJson(e))
          .toList();
    }
    
    // 解析导演信息
    List<JellyfinPerson> directors = [];
    if (json['People'] != null) {
      directors = (json['People'] as List)
          .where((person) => person['Type'] == 'Director')
          .map((e) => JellyfinPerson.fromJson(e))
          .toList();
    }
    
    // 解析流派
    List<String> genres = [];
    if (json['Genres'] != null) {
      genres = List<String>.from(json['Genres']);
    }
    
    return JellyfinMediaItemDetail(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      originalTitle: json['OriginalTitle'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      imageBackdropTag: json['BackdropImageTags']?.isNotEmpty == true ? json['BackdropImageTags'][0] : null,
      productionYear: json['ProductionYear'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      communityRating: json['CommunityRating']?.toString(),
      genres: genres,
      officialRating: json['OfficialRating'],
      cast: cast,
      directors: directors,
      runTimeTicks: json['RunTimeTicks'],
      seriesStudio: json['Studios']?.isNotEmpty == true ? json['Studios'][0]['Name'] : null,
      type: json['Type'] ?? 'Unknown', // 新增type字段
    );
  }
}

// Jellyfin剧集季节信息
class JellyfinSeasonInfo {
  final String id;
  final String name;
  final String? seriesId;
  final String? seriesName;
  final String? imagePrimaryTag;
  final int? indexNumber;
  
  JellyfinSeasonInfo({
    required this.id,
    required this.name,
    this.seriesId,
    this.seriesName,
    this.imagePrimaryTag,
    this.indexNumber,
  });
  
  factory JellyfinSeasonInfo.fromJson(Map<String, dynamic> json) {
    return JellyfinSeasonInfo(
      id: json['Id'],
      name: json['Name'],
      seriesId: json['SeriesId'],
      seriesName: json['SeriesName'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      indexNumber: json['IndexNumber'],
    );
  }
}

// Jellyfin剧集信息
class JellyfinEpisodeInfo {
  final String id;
  final String name;
  final String? overview;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seasonName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? imagePrimaryTag;
  final DateTime dateAdded;
  final String? premiereDate;
  final int? runTimeTicks;
  
  JellyfinEpisodeInfo({
    required this.id,
    required this.name,
    this.overview,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seasonName,
    this.indexNumber,
    this.parentIndexNumber,
    this.imagePrimaryTag,
    required this.dateAdded,
    this.premiereDate,
    this.runTimeTicks,
  });
  
  factory JellyfinEpisodeInfo.fromJson(Map<String, dynamic> json) {
    return JellyfinEpisodeInfo(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      seriesId: json['SeriesId'],
      seriesName: json['SeriesName'],
      seasonId: json['SeasonId'],
      seasonName: json['SeasonName'],
      indexNumber: json['IndexNumber'],
      parentIndexNumber: json['ParentIndexNumber'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      runTimeTicks: json['RunTimeTicks'],
    );
  }
  
  // 将JellyfinEpisodeInfo转换为WatchHistoryItem，用于与现有系统兼容
  WatchHistoryItem toWatchHistoryItem({int? lastPosition = 0, int? duration = 0}) {
    String safeName = seriesName ?? '';
    if (safeName.isEmpty) safeName = "未知剧集";
    
    return WatchHistoryItem(
      filePath: 'jellyfin://$id', // 使用jellyfin://协议来区分本地文件，实际播放时需要替换为真实的流媒体URL
      animeName: safeName,
      episodeTitle: name,
      watchProgress: 0.0,
      lastPosition: lastPosition ?? 0,
      duration: duration ?? 0,
      lastWatchTime: DateTime.now(),
      animeId: null, // 初始值为null，但会通过JellyfinDandanplayMatcher更新
      episodeId: null, // 初始值为null，但会通过JellyfinDandanplayMatcher更新
      isFromScan: false,
    );
  }
}

// Jellyfin人员信息（演员、导演等）
class JellyfinPerson {
  final String id;
  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;
  
  JellyfinPerson({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });
  
  factory JellyfinPerson.fromJson(Map<String, dynamic> json) {
    return JellyfinPerson(
      id: json['Id'],
      name: json['Name'],
      role: json['Role'],
      type: json['Type'],
      primaryImageTag: json['PrimaryImageTag'],
    );
  }
}

// Jellyfin电影信息
class JellyfinMovieInfo {
  final String id;
  final String name;
  final String? overview;
  final String? originalTitle;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final int? productionYear;
  final DateTime dateAdded;
  final String? premiereDate;
  final String? communityRating;
  final List<String> genres;
  final String? officialRating;
  final List<JellyfinPerson> cast;
  final List<JellyfinPerson> directors;
  final int? runTimeTicks;
  final String? studio;
  
  JellyfinMovieInfo({
    required this.id,
    required this.name,
    this.overview,
    this.originalTitle,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.productionYear,
    required this.dateAdded,
    this.premiereDate,
    this.communityRating,
    required this.genres,
    this.officialRating,
    required this.cast,
    required this.directors,
    this.runTimeTicks,
    this.studio,
  });
  
  factory JellyfinMovieInfo.fromJson(Map<String, dynamic> json) {
    // 解析演员信息
    List<JellyfinPerson> cast = [];
    if (json['People'] != null) {
      cast = (json['People'] as List)
          .where((person) => person['Type'] == 'Actor')
          .map((e) => JellyfinPerson.fromJson(e))
          .toList();
    }
    
    // 解析导演信息
    List<JellyfinPerson> directors = [];
    if (json['People'] != null) {
      directors = (json['People'] as List)
          .where((person) => person['Type'] == 'Director')
          .map((e) => JellyfinPerson.fromJson(e))
          .toList();
    }
    
    // 解析流派
    List<String> genres = [];
    if (json['Genres'] != null) {
      genres = List<String>.from(json['Genres']);
    }
    
    return JellyfinMovieInfo(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      originalTitle: json['OriginalTitle'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      imageBackdropTag: json['BackdropImageTags']?.isNotEmpty == true ? json['BackdropImageTags'][0] : null,
      productionYear: json['ProductionYear'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      communityRating: json['CommunityRating']?.toString(),
      genres: genres,
      officialRating: json['OfficialRating'],
      cast: cast,
      directors: directors,
      runTimeTicks: json['RunTimeTicks'],
      studio: json['Studios']?.isNotEmpty == true ? json['Studios'][0]['Name'] : null,
    );
  }
  
  // 将JellyfinMovieInfo转换为WatchHistoryItem，用于与现有系统兼容
  WatchHistoryItem toWatchHistoryItem({int? lastPosition = 0, int? duration = 0}) {
    return WatchHistoryItem(
      filePath: 'jellyfin://$id', // 使用jellyfin://协议来区分本地文件
      animeName: name,
      episodeTitle: null, // 电影没有集标题
      watchProgress: 0.0,
      lastPosition: lastPosition ?? 0,
      duration: duration ?? 0,
      lastWatchTime: DateTime.now(),
      animeId: null, // 初始值为null，但会通过JellyfinDandanplayMatcher更新
      episodeId: null, // 初始值为null，但会通过JellyfinDandanplayMatcher更新
      isFromScan: false,
    );
  }
}
