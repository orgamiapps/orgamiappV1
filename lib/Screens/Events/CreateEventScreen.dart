import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';
import 'package:orgami/Screens/Home/DashboardScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/TextFields.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class CreateEventScreen extends StatefulWidget {
  final DateTime selectedDateTime;
  final LatLng selectedLocation;
  final double radios;

  const CreateEventScreen({
    super.key,
    required this.selectedDateTime,
    required this.selectedLocation,
    required this.radios,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool successMessage = false;
  final _btnCtlr = RoundedLoadingButtonController();

  bool privateEvent = false;

  final TextEditingController groupNameEdtController = TextEditingController();
  final TextEditingController titleEdtController = TextEditingController();
  final TextEditingController locationEdtController = TextEditingController();
  final TextEditingController thumbnailUrlCtlr = TextEditingController();
  final TextEditingController descriptionEdtController =
      TextEditingController();

  String? _selectedImagePath;

  Future _pickImage() async {
    final ImagePicker picker = ImagePicker();
    XFile? image = await picker.pickImage(
        source: ImageSource.gallery, maxHeight: 600, maxWidth: 1000);
    if (image != null) {
      setState(() {
        _selectedImagePath = image.path;
        thumbnailUrlCtlr.text = image.path;
      });
    }
  }

  Future<String?> _uploadToFirebaseHosting() async {
    //return download link
    String? imageUrl;
    Uint8List imageData = await XFile(_selectedImagePath!).readAsBytes();
    final Reference storageReference = FirebaseStorage.instance
        .ref()
        .child('events_images/${_selectedImagePath.hashCode}.png');
    final SettableMetadata metadata =
        SettableMetadata(contentType: 'image/png');
    final UploadTask uploadTask = storageReference.putData(imageData, metadata);
    await uploadTask.whenComplete(() async {
      imageUrl = await storageReference.getDownloadURL();
    });
    return imageUrl;
  }

  void _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      _btnCtlr.start();
      if (_selectedImagePath != null) {
        //local image
        await _uploadToFirebaseHosting().then((String? imgUrl) async {
          if (imgUrl != null) {
            setState(() => thumbnailUrlCtlr.text = imgUrl);
            uploadEvent();
          } else {
            setState(() {
              _selectedImagePath = null;
              thumbnailUrlCtlr.clear();
            });
            _btnCtlr.reset();
          }
        });
      } else {
        //network image
        uploadEvent();
      }
    }
  }

  Future uploadEvent() async {
    await FirebaseFirestoreHelper().getEventID().then((docId) async {
      EventModel newEvent = EventModel(
        id: docId,
        groupName: groupNameEdtController.text,
        title: titleEdtController.text,
        description: descriptionEdtController.text,
        location: locationEdtController.text,
        customerUid: FirebaseAuth.instance.currentUser!.uid,
        imageUrl: thumbnailUrlCtlr.text,
        selectedDateTime: widget.selectedDateTime,
        eventGenerateTime: DateTime.now(),
        status: '',
        getLocation: true,
        radius: widget.radios,
        longitude: widget.selectedLocation.longitude,
        latitude: widget.selectedLocation.latitude,
        private: privateEvent,
      );

      Map<String, dynamic> data = newEvent.toJson();

      FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(docId)
          .set(data)
          .then((value) {
        debugPrint('Event Uploaded!');
        _btnCtlr.success();
        RouterClass.nextScreenAndReplacementAndRemoveUntil(
          context: context,
          page: const DashboardScreen(),
        );
        RouterClass.nextScreenNormal(
          context,
          SingleEventScreen(eventModel: newEvent),
          // AddQuestionsToEventScreen(eventModel: newEvent),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _bodyView(),
          // successMessage
          //     ? SuccessfulDialog(backButtonCalled: () {
          //         setState(() {
          //           successMessage = false;
          //         });
          //       })
          //     : const SizedBox(),
        ],
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: AppAppBarView.appBarView(
                context: context,
                title: 'Event Details',
              ),
            ),
            Expanded(
              child: _detailsView(),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
              child: RoundedLoadingButton(
                animateOnTap: false,
                borderRadius: 5,
                width: 300,
                controller: _btnCtlr,
                onPressed: () => _handleSubmit(),
                color: AppThemeColor.darkGreenColor,
                elevation: 0,
                child: const Wrap(
                  children: [
                    Text(
                      'Add New Event',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsView() {
    return Container(
      width: _screenWidth,
      margin: const EdgeInsets.symmetric(
        horizontal: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.all(15),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Let\'s get started by filling out the form below.',
                style: TextStyle(
                  color: AppThemeColor.pureBlackColor,
                  fontSize: Dimensions.fontSizeLarge,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _singleWithIconValue(
                iconData: Icons.calendar_month_rounded,
                value: DateFormat('EEEE dd MMMM').format(
                  widget.selectedDateTime,
                ),
              ),
              _singleWithIconValue(
                iconData: Icons.access_time_rounded,
                value: DateFormat('KK:mm a').format(
                  widget.selectedDateTime,
                ),
              ),
              _privateEventCheckBoxView(),
              AppTextFields.TextField2(
                hintText: 'Type here...',
                titleText: 'Organizer',
                width: _screenWidth,
                controller: groupNameEdtController,
                validator: (value) {
                  if (value!.isEmpty) {
                    return 'Enter Organizer first!';
                  }
                  return null;
                },
              ),
              AppTextFields.TextField2(
                hintText: 'Type here...',
                titleText: 'Title',
                width: _screenWidth,
                controller: titleEdtController,
                validator: (value) {
                  if (value!.isEmpty) {
                    return 'Enter Title first!';
                  }
                  return null;
                },
              ),
              const SizedBox(
                height: 5,
              ),
              Row(
                children: [
                  Expanded(
                    child: AppTextFields.TextField2(
                      hintText: 'Enter Image Url or Select Image',
                      titleText: 'Image',
                      width: _screenWidth,
                      controller: thumbnailUrlCtlr,
                      validator: (value) {
                        if (value!.isEmpty) return 'Value is empty';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Container(
                    height: 50,
                    width: 50,
                    alignment: Alignment.center,
                    child: DottedBorder(
                      radius: const Radius.circular(10),
                      color: Colors.grey,
                      child: IconButton(
                        tooltip: 'Select Image',
                        icon: const Icon(Icons.image_outlined),
                        onPressed: () => _pickImage(),
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(
                height: 5,
              ),
              AppTextFields.TextField2(
                hintText: 'Type here...',
                titleText: 'Location',
                width: _screenWidth,
                controller: locationEdtController,
                validator: (value) {
                  if (value!.isEmpty) {
                    return 'Enter Location first!';
                  }
                  return null;
                },
              ),
              AppTextFields.TextField2(
                controller: descriptionEdtController,
                hintText: 'Type here...',
                titleText: 'Description',
                width: _screenWidth,
                maxLines: 4,
                validator: (value) {
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _privateEventCheckBoxView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          const Text(
            'Private Event',
            style: TextStyle(
              color: AppThemeColor.pureBlackColor,
              fontWeight: FontWeight.w500,
              fontSize: Dimensions.fontSizeLarge,
            ),
          ),
          Checkbox(
              value: privateEvent,
              onChanged: (p) {
                setState(() {
                  privateEvent = p!;
                });
              })
        ],
      ),
    );
  }

  Widget _singleWithIconValue(
      {required IconData iconData, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            iconData,
            size: 33,
            color: AppThemeColor.pureBlackColor,
          ),
          const SizedBox(
            width: 10,
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppThemeColor.dullFontColor,
              fontWeight: FontWeight.w500,
              fontSize: Dimensions.fontSizeLarge,
            ),
          )
        ],
      ),
    );
  }
}
