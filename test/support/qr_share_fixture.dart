import 'package:attendus/models/event_model.dart';

EventModel qrShareFixture() => EventModel(
  id: 'qr-share-fixture',
  groupName: '',
  title: 'Community garden gathering',
  description: '',
  location: 'Riverside Park',
  customerUid: 'owner',
  imageUrl: '',
  selectedDateTime: DateTime.utc(2027, 6, 1, 18),
  eventGenerateTime: DateTime.utc(2027),
  eventTimeZone: 'America/New_York',
  eventDurationMinutes: 90,
  status: 'scheduled',
  private: false,
  getLocation: false,
  radius: 0,
  latitude: 0,
  longitude: 0,
);
