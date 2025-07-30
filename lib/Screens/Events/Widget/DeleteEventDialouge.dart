import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class DeleteEventDialoge extends StatefulWidget {
  final EventModel singleEvent;

  const DeleteEventDialoge({super.key, required this.singleEvent});

  @override
  State<DeleteEventDialoge> createState() => _DeleteEventDialogeState();
}

class _DeleteEventDialogeState extends State<DeleteEventDialoge> {
  late final EventModel singleEvent = widget.singleEvent;
  late double _screenWidth;
  late double _screenHeight;
  final _btnCtlr = RoundedLoadingButtonController();

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;
    _screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
        backgroundColor: const Color(0x998F8F8F),
        body: SafeArea(
          child: _bodyView(context: context),
        ));
  }

  Widget _bodyView({required BuildContext context}) {
    return Center(
      child: Container(
        width: _screenWidth / 1.1,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              width: _screenWidth / 1.3,
              padding: const EdgeInsets.only(
                  top: 40, bottom: 15, left: 20, right: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Warning!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    'Are you sure you want to delete this event?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                  RoundedLoadingButton(
                    animateOnTap: false,
                    borderRadius: 5,
                    controller: _btnCtlr,
                    onPressed: () {
                      try {
                        _btnCtlr.start();
                        FirebaseFirestore.instance
                            .collection(EventModel.firebaseKey)
                            .doc(singleEvent.id)
                            .delete()
                            .then((value) {
                          ShowToast().showNormalToast(msg: 'Deleted!');
                          RouterClass().homeScreenRoute(context: context);
                        });
                      } catch (e) {
                        _btnCtlr.reset();
                      }
                    },
                    color: Colors.red,
                    elevation: 0,
                    child: const Wrap(
                      children: [
                        Text(
                          'Delete',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 20,
              child: IconButton(
                icon: const Icon(FontAwesomeIcons.xmark),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
