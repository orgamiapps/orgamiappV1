/// Public discovery must never advertise drafts or moderated/tombstoned events.
/// Keep the raw-document check before model defaults can erase missing fields.
bool isDiscoverableEventData(Map<String, dynamic> data) {
  final status = data['status'];
  return data['private'] == false &&
      (status == 'active' || status == 'scheduled') &&
      data['isHidden'] != true &&
      data['deleted'] != true;
}
