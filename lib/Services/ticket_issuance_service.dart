import 'package:attendus/models/ticket_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

abstract final class TicketIssuanceService {
  static Future<TicketModel> issueFreeTicket({required String eventId}) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('issueFreeTicket');
    final response = await callable.call<Map<String, dynamic>>({
      'eventId': eventId,
    });
    final ticketId = response.data['ticketId'];
    if (ticketId is! String || ticketId.isEmpty) {
      throw StateError('The ticket service returned an invalid ticket ID.');
    }
    final snapshot = await FirebaseFirestore.instance
        .collection(TicketModel.firebaseKey)
        .doc(ticketId)
        .get();
    if (!snapshot.exists) {
      throw StateError('The issued ticket could not be loaded.');
    }
    return TicketModel.fromJson(snapshot);
  }
}
