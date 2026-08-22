import 'package:attendus/models/check_in_policy.dart';
import 'package:attendus/models/event_model.dart';

enum EventWizardStage { basics, registration, experience, publish }

enum EventWizardSaveState {
  idle,
  saving,
  saved,
  savedOnDevice,
  offline,
  failed,
}

enum EventRegistrationMode { rsvp, freeTicket, paidTicket }

enum EventApprovalMode { automatic, manual }

enum EventQuestionType {
  shortText,
  longText,
  singleChoice,
  multipleChoice,
  acknowledgement,
}

enum EventQuestionTiming { registration, checkIn }

enum EventRecurrenceFrequency { daily, weekly, weekdays, monthly }

enum EventReminderPreset { off, dayBefore, hourBefore, dayAndHour }

String _enumName(Enum value) => switch (value) {
  EventRegistrationMode.freeTicket => 'free_ticket',
  EventRegistrationMode.paidTicket => 'paid_ticket',
  EventQuestionType.shortText => 'short_text',
  EventQuestionType.longText => 'long_text',
  EventQuestionType.singleChoice => 'single_choice',
  EventQuestionType.multipleChoice => 'multiple_choice',
  EventQuestionTiming.checkIn => 'check_in',
  EventReminderPreset.dayBefore => '24h',
  EventReminderPreset.hourBefore => '1h',
  EventReminderPreset.dayAndHour => '24h_1h',
  _ => value.name,
};

T _enumFrom<T extends Enum>(Iterable<T> values, dynamic raw, T fallback) {
  final value = raw?.toString();
  return values.where((item) => _enumName(item) == value).firstOrNull ??
      fallback;
}

class EventWizardQuestion {
  EventWizardQuestion({
    required this.id,
    required this.prompt,
    this.type = EventQuestionType.longText,
    this.timing = EventQuestionTiming.checkIn,
    this.required = false,
    this.options = const [],
  });

  final String id;
  String prompt;
  EventQuestionType type;
  EventQuestionTiming timing;
  bool required;
  List<String> options;

  factory EventWizardQuestion.fromJson(Map<String, dynamic> json) =>
      EventWizardQuestion(
        id: json['id']?.toString() ?? '',
        prompt:
            json['prompt']?.toString() ??
            json['questionTitle']?.toString() ??
            '',
        type: _enumFrom(
          EventQuestionType.values,
          json['type'],
          EventQuestionType.longText,
        ),
        timing: _enumFrom(
          EventQuestionTiming.values,
          json['timing'],
          EventQuestionTiming.checkIn,
        ),
        required: json['required'] == true,
        options: json['options'] is List
            ? List<String>.from(json['options'])
            : const [],
      );

  Map<String, dynamic> toJson(int order) => {
    'id': id,
    'prompt': prompt.trim(),
    'questionTitle': prompt.trim(),
    'type': _enumName(type),
    'timing': _enumName(timing),
    'required': required,
    'options': options
        .map((value) => value.trim())
        .where((v) => v.isNotEmpty)
        .toList(),
    'order': order,
    'version': 2,
  };
}

class EventWizardAgendaItem {
  EventWizardAgendaItem({
    required this.id,
    required this.title,
    this.details = '',
    this.offsetMinutes = 0,
  });

  final String id;
  String title;
  String details;
  int offsetMinutes;

  factory EventWizardAgendaItem.fromJson(Map<String, dynamic> json) =>
      EventWizardAgendaItem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        offsetMinutes: (json['offsetMinutes'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toJson(int order) => {
    'id': id,
    'title': title.trim(),
    'details': details.trim(),
    'offsetMinutes': offsetMinutes,
    'order': order,
  };
}

class EventWizardTemplate {
  const EventWizardTemplate({
    required this.id,
    required this.label,
    required this.categoryId,
    required this.iconName,
    this.locationType = 'in_person',
    this.durationMinutes = 120,
    this.registrationMode = EventRegistrationMode.rsvp,
    this.attendanceProfile = CheckInProfile.hybrid,
  });

  final String id;
  final String label;
  final String categoryId;
  final String iconName;
  final String locationType;
  final int durationMinutes;
  final EventRegistrationMode registrationMode;
  final CheckInProfile attendanceProfile;

  static const curated = [
    EventWizardTemplate(
      id: 'community_meetup',
      label: 'Community meetup',
      categoryId: 'community-causes',
      iconName: 'groups',
    ),
    EventWizardTemplate(
      id: 'networking',
      label: 'Networking event',
      categoryId: 'business-networking',
      iconName: 'handshake',
    ),
    EventWizardTemplate(
      id: 'workshop',
      label: 'Class or workshop',
      categoryId: 'classes-workshops',
      iconName: 'school',
      registrationMode: EventRegistrationMode.freeTicket,
    ),
    EventWizardTemplate(
      id: 'conference',
      label: 'Conference or panel',
      categoryId: 'business-networking',
      iconName: 'podium',
      durationMinutes: 240,
      registrationMode: EventRegistrationMode.freeTicket,
      attendanceProfile: CheckInProfile.staffEntry,
    ),
    EventWizardTemplate(
      id: 'webinar',
      label: 'Online webinar',
      categoryId: 'technology-innovation',
      iconName: 'videocam',
      locationType: 'online',
      durationMinutes: 60,
      attendanceProfile: CheckInProfile.selfCheckIn,
    ),
    EventWizardTemplate(
      id: 'music_social',
      label: 'Music or social event',
      categoryId: 'music-nightlife',
      iconName: 'music',
      durationMinutes: 180,
      registrationMode: EventRegistrationMode.freeTicket,
    ),
    EventWizardTemplate(
      id: 'fitness_outdoor',
      label: 'Fitness or outdoor activity',
      categoryId: 'sports-fitness',
      iconName: 'fitness',
      durationMinutes: 90,
    ),
    EventWizardTemplate(
      id: 'fundraiser',
      label: 'Fundraiser or volunteer event',
      categoryId: 'community-causes',
      iconName: 'volunteer',
      durationMinutes: 180,
    ),
  ];
}

class EventWizardDraft {
  EventWizardDraft({
    this.draftId,
    this.revision = 0,
    this.mode = 'create',
    this.sourceEventId,
    this.sourceSeriesId,
    this.sourceEventRevision,
    this.currentStage = EventWizardStage.basics,
    this.title = '',
    this.description = '',
    this.imageUrl = '',
    required this.startAt,
    required this.endAt,
    this.eventTimeZone = 'UTC',
    this.locationType = 'in_person',
    this.location = '',
    this.locationName = '',
    this.placeId = '',
    this.city = '',
    this.regionCode = '',
    this.countryCode = 'US',
    this.streetAddress = '',
    this.postalCode = '',
    this.latitude = 0,
    this.longitude = 0,
    this.radius = 30,
    this.organizationId,
    this.isPrivate = false,
    this.primaryDiscoveryCategoryId,
    this.discoveryCategoryIds = const [],
    this.registrationMode = EventRegistrationMode.rsvp,
    this.capacity,
    this.approvalMode = EventApprovalMode.automatic,
    this.waitlistEnabled = true,
    this.registrationOpensAt,
    this.registrationClosesAt,
    this.priceUsd = 0,
    this.refundTerms = '',
    this.questions = const [],
    this.agenda = const [],
    this.accessibilityOptions = const [],
    this.accessibilityDetails = '',
    this.thingsToBring = const [],
    this.publicContactName = '',
    this.publicContactEmail = '',
    this.publicContactVisible = false,
    this.coHosts = const [],
    this.checkInStaff = const [],
    this.checkInPolicy = const CheckInPolicy(),
    this.recurrenceEnabled = false,
    this.recurrenceFrequency = EventRecurrenceFrequency.weekly,
    this.recurrenceInterval = 1,
    this.recurrenceWeekDays = const [],
    this.recurrenceEndMode = 'count',
    this.recurrenceCount = 2,
    this.recurrenceEndDate,
    this.reminderPreset = EventReminderPreset.dayAndHour,
  });

  String? draftId;
  int revision;
  String mode;
  String? sourceEventId;
  String? sourceSeriesId;
  int? sourceEventRevision;
  EventWizardStage currentStage;
  String title;
  String description;
  String imageUrl;
  DateTime startAt;
  DateTime endAt;
  String eventTimeZone;
  String locationType;
  String location;
  String locationName;
  String placeId;
  String city;
  String regionCode;
  String countryCode;
  String streetAddress;
  String postalCode;
  double latitude;
  double longitude;
  double radius;
  String? organizationId;
  bool isPrivate;
  String? primaryDiscoveryCategoryId;
  List<String> discoveryCategoryIds;
  EventRegistrationMode registrationMode;
  int? capacity;
  EventApprovalMode approvalMode;
  bool waitlistEnabled;
  DateTime? registrationOpensAt;
  DateTime? registrationClosesAt;
  double priceUsd;
  String refundTerms;
  List<EventWizardQuestion> questions;
  List<EventWizardAgendaItem> agenda;
  List<String> accessibilityOptions;
  String accessibilityDetails;
  List<String> thingsToBring;
  String publicContactName;
  String publicContactEmail;
  bool publicContactVisible;
  List<String> coHosts;
  List<String> checkInStaff;
  CheckInPolicy checkInPolicy;
  bool recurrenceEnabled;
  EventRecurrenceFrequency recurrenceFrequency;
  int recurrenceInterval;
  List<int> recurrenceWeekDays;
  String recurrenceEndMode;
  int recurrenceCount;
  DateTime? recurrenceEndDate;
  EventReminderPreset reminderPreset;

  factory EventWizardDraft.blank({
    DateTime? selectedDateTime,
    int durationHours = 1,
    String? organizationId,
    bool forcePrivate = false,
  }) {
    final now = DateTime.now();
    final rawStart = selectedDateTime ?? now.add(const Duration(hours: 1));
    final start = DateTime(
      rawStart.year,
      rawStart.month,
      rawStart.day,
      rawStart.hour,
      rawStart.minute < 30 ? 30 : 0,
    ).add(rawStart.minute >= 30 ? const Duration(hours: 1) : Duration.zero);
    return EventWizardDraft(
      startAt: start,
      endAt: start.add(Duration(hours: durationHours)),
      organizationId: organizationId,
      isPrivate: forcePrivate || organizationId != null,
    );
  }

  factory EventWizardDraft.fromEvent(EventModel event) => EventWizardDraft(
    mode: 'edit',
    sourceEventId: event.id,
    sourceSeriesId: null,
    sourceEventRevision: event.eventRevision,
    title: event.title,
    description: event.description,
    imageUrl: event.imageUrl,
    startAt: event.selectedDateTime,
    endAt: event.eventEndTime,
    eventTimeZone: event.eventTimeZone,
    locationType: event.locationType,
    location: event.location,
    locationName: event.locationName ?? '',
    placeId: event.placeId ?? '',
    city: event.city,
    regionCode: event.regionCode,
    countryCode: event.countryCode,
    streetAddress: event.streetAddress,
    postalCode: event.postalCode,
    latitude: event.latitude,
    longitude: event.longitude,
    radius: event.radius,
    organizationId: event.organizationId,
    isPrivate: event.private,
    primaryDiscoveryCategoryId: event.primaryDiscoveryCategoryId,
    discoveryCategoryIds: List.of(event.discoveryCategoryIds),
    registrationMode: !event.ticketsEnabled
        ? EventRegistrationMode.rsvp
        : (event.ticketPrice ?? 0) > 0
        ? EventRegistrationMode.paidTicket
        : EventRegistrationMode.freeTicket,
    capacity: event.maxTickets > 0 ? event.maxTickets : null,
    priceUsd: event.ticketPrice ?? 0,
    coHosts: List.of(event.coHosts),
    checkInStaff: List.of(event.checkInStaff),
    checkInPolicy: event.checkInPolicy,
  );

  factory EventWizardDraft.fromJson(Map<String, dynamic> json) {
    final form = Map<String, dynamic>.from(json['formData'] as Map? ?? json);
    final registration = Map<String, dynamic>.from(
      form['registration'] as Map? ?? {},
    );
    final experience = Map<String, dynamic>.from(
      form['experience'] as Map? ?? {},
    );
    final contact = Map<String, dynamic>.from(
      experience['publicContact'] as Map? ?? {},
    );
    final recurrence = Map<String, dynamic>.from(
      form['recurrence'] as Map? ?? {},
    );
    final start =
        DateTime.tryParse(form['startAt']?.toString() ?? '') ?? DateTime.now();
    final end =
        DateTime.tryParse(form['endAt']?.toString() ?? '') ??
        start.add(const Duration(hours: 1));
    return EventWizardDraft(
      draftId: json['id']?.toString() ?? json['draftId']?.toString(),
      revision: (json['revision'] as num?)?.round() ?? 0,
      mode: json['mode']?.toString() ?? 'create',
      sourceEventId: json['sourceEventId']?.toString(),
      sourceSeriesId: json['sourceSeriesId']?.toString(),
      sourceEventRevision: (json['sourceEventRevision'] as num?)?.round(),
      currentStage: EventWizardStage
          .values[(json['currentStage'] as num?)?.round().clamp(0, 3) ?? 0],
      title: form['title']?.toString() ?? '',
      description: form['description']?.toString() ?? '',
      imageUrl: form['imageUrl']?.toString() ?? '',
      startAt: start,
      endAt: end,
      eventTimeZone: form['eventTimeZone']?.toString() ?? 'UTC',
      locationType: form['locationType'] == 'online' ? 'online' : 'in_person',
      location: form['location']?.toString() ?? '',
      locationName: form['locationName']?.toString() ?? '',
      placeId: form['placeId']?.toString() ?? '',
      city: form['city']?.toString() ?? '',
      regionCode: form['regionCode']?.toString() ?? '',
      countryCode: form['countryCode']?.toString() ?? 'US',
      streetAddress: form['streetAddress']?.toString() ?? '',
      postalCode: form['postalCode']?.toString() ?? '',
      latitude: (form['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (form['longitude'] as num?)?.toDouble() ?? 0,
      radius: (form['radius'] as num?)?.toDouble() ?? 30,
      organizationId: form['organizationId']?.toString(),
      isPrivate: form['private'] == true,
      primaryDiscoveryCategoryId: form['primaryDiscoveryCategoryId']
          ?.toString(),
      discoveryCategoryIds: form['discoveryCategoryIds'] is List
          ? List<String>.from(form['discoveryCategoryIds'])
          : [],
      registrationMode: _enumFrom(
        EventRegistrationMode.values,
        registration['mode'],
        EventRegistrationMode.rsvp,
      ),
      capacity: (registration['capacity'] as num?)?.round(),
      approvalMode: _enumFrom(
        EventApprovalMode.values,
        registration['approvalMode'],
        EventApprovalMode.automatic,
      ),
      waitlistEnabled: registration['waitlistEnabled'] != false,
      registrationOpensAt: DateTime.tryParse(
        registration['opensAt']?.toString() ?? '',
      ),
      registrationClosesAt: DateTime.tryParse(
        registration['closesAt']?.toString() ?? '',
      ),
      priceUsd: (registration['priceUsd'] as num?)?.toDouble() ?? 0,
      refundTerms: registration['refundTerms']?.toString() ?? '',
      questions: (form['questions'] as List? ?? [])
          .map(
            (item) => EventWizardQuestion.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      agenda: (experience['agenda'] as List? ?? [])
          .map(
            (item) => EventWizardAgendaItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      accessibilityOptions: experience['accessibilityOptions'] is List
          ? List<String>.from(experience['accessibilityOptions'])
          : [],
      accessibilityDetails:
          experience['accessibilityDetails']?.toString() ?? '',
      thingsToBring: experience['thingsToBring'] is List
          ? List<String>.from(experience['thingsToBring'])
          : [],
      publicContactName: contact['name']?.toString() ?? '',
      publicContactEmail: contact['email']?.toString() ?? '',
      publicContactVisible: contact['visible'] == true,
      coHosts: experience['coHosts'] is List
          ? List<String>.from(experience['coHosts'])
          : [],
      checkInStaff: experience['checkInStaff'] is List
          ? List<String>.from(experience['checkInStaff'])
          : [],
      checkInPolicy: CheckInPolicy.fromJson(
        experience['checkInPolicy'] is Map
            ? Map<String, dynamic>.from(experience['checkInPolicy'])
            : null,
      ),
      recurrenceEnabled: recurrence['enabled'] == true,
      recurrenceFrequency: _enumFrom(
        EventRecurrenceFrequency.values,
        recurrence['frequency'],
        EventRecurrenceFrequency.weekly,
      ),
      recurrenceInterval: (recurrence['interval'] as num?)?.round() ?? 1,
      recurrenceWeekDays: recurrence['weekDays'] is List
          ? List<int>.from(recurrence['weekDays'])
          : [],
      recurrenceEndMode: recurrence['endMode'] == 'date' ? 'date' : 'count',
      recurrenceCount: (recurrence['occurrenceCount'] as num?)?.round() ?? 2,
      recurrenceEndDate: DateTime.tryParse(
        recurrence['endDate']?.toString() ?? '',
      ),
      reminderPreset: _enumFrom(
        EventReminderPreset.values,
        form['reminderPreset'],
        EventReminderPreset.dayAndHour,
      ),
    );
  }

  Map<String, dynamic> toFormJson() => {
    'title': title.trim(),
    'description': description.trim(),
    'imageUrl': imageUrl.trim(),
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'eventTimeZone': eventTimeZone,
    'locationType': locationType,
    'location': location.trim(),
    'locationName': locationName.trim(),
    'placeId': placeId,
    'city': city,
    'regionCode': regionCode,
    'countryCode': countryCode,
    'streetAddress': streetAddress,
    'postalCode': postalCode,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'organizationId': organizationId,
    'private': isPrivate,
    'primaryDiscoveryCategoryId': primaryDiscoveryCategoryId,
    'discoveryCategoryIds': discoveryCategoryIds,
    'registration': {
      'mode': _enumName(registrationMode),
      'capacity': capacity,
      'approvalMode': _enumName(approvalMode),
      'waitlistEnabled': waitlistEnabled,
      'opensAt': registrationOpensAt?.toIso8601String(),
      'closesAt': registrationClosesAt?.toIso8601String(),
      'priceUsd': priceUsd,
      'refundTerms': refundTerms.trim(),
    },
    'questions': [
      for (var index = 0; index < questions.length; index++)
        questions[index].toJson(index),
    ],
    'experience': {
      'agenda': [
        for (var index = 0; index < agenda.length; index++)
          agenda[index].toJson(index),
      ],
      'accessibilityOptions': accessibilityOptions,
      'accessibilityDetails': accessibilityDetails.trim(),
      'thingsToBring': thingsToBring,
      'publicContact': {
        'name': publicContactName.trim(),
        'email': publicContactEmail.trim(),
        'visible': publicContactVisible,
      },
      'coHosts': coHosts,
      'checkInStaff': checkInStaff,
      'checkInPolicy': checkInPolicy.toJson(),
    },
    'recurrence': {
      'enabled': recurrenceEnabled,
      if (recurrenceEnabled) ...{
        'frequency': _enumName(recurrenceFrequency),
        'interval': recurrenceInterval,
        'weekDays': recurrenceWeekDays,
        'endMode': recurrenceEndMode,
        'occurrenceCount': recurrenceCount,
        'endDate': recurrenceEndDate?.toIso8601String().split('T').first,
      },
    },
    'reminderPreset': _enumName(reminderPreset),
  };

  void applyTemplate(EventWizardTemplate template) {
    locationType = template.locationType;
    endAt = startAt.add(Duration(minutes: template.durationMinutes));
    registrationMode = template.registrationMode;
    primaryDiscoveryCategoryId = template.categoryId;
    discoveryCategoryIds = [template.categoryId];
    checkInPolicy = checkInPolicy.copyWith(profile: template.attendanceProfile);
  }
}
