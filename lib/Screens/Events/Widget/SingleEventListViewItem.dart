import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Screens/Events/SingleEventScreen.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/Utils/dimensions.dart';

class SingleEventListViewItem extends StatelessWidget {
  final EventModel eventModel;
  const SingleEventListViewItem({super.key, required this.eventModel});

  @override
  Widget build(BuildContext context) {
    double? screenWidth = MediaQuery.of(context).size.width;
    return GestureDetector(
      onTap: () => RouterClass.nextScreenNormal(
        context,
        SingleEventScreen(eventModel: eventModel),
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  spreadRadius: 1,
                  blurRadius: 7,
                  offset: Offset(0, 1), // changes position of shadow
                ),
              ],
            ),
            width: screenWidth,
            // height: tabHeight,
            padding: const EdgeInsets.all(7),

            margin: const EdgeInsets.only(
              top: 8,
              bottom: 8,
              right: 20,
              left: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    if (eventModel.isFeatured)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: Icon(
                          Icons.star,
                          color: AppThemeColor.orangeColor,
                          size: Dimensions.fontSizeLarge + 4,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        eventModel.title,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppThemeColor.pureBlackColor,
                          fontWeight: FontWeight.w700,
                          fontSize: Dimensions.fontSizeLarge,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: screenWidth,
                  child: Text(
                    eventModel.groupName,
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppThemeColor.dullFontColor,
                      fontWeight: FontWeight.w600,
                      fontSize: Dimensions.fontSizeSmall,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 7,
                ),
                SizedBox(
                  width: screenWidth,
                  child: Text(
                    eventModel.location,
                    style: const TextStyle(
                      color: AppThemeColor.dullFontColor,
                      fontWeight: FontWeight.w600,
                      fontSize: Dimensions.fontSizeSmall,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 7,
                ),
                SizedBox(
                  height: screenWidth / 2,
                  child: CustomCacheImage(
                    imageUrl: eventModel.imageUrl,
                    radius: 0,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                SizedBox(
                  width: screenWidth,
                  child: Text(
                    eventModel.description,
                    style: const TextStyle(
                      color: AppThemeColor.pureBlackColor,
                      fontWeight: FontWeight.w400,
                      fontSize: Dimensions.fontSizeSmall,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${DateFormat('EEEE, MMMM dd yyyy').format(
                                eventModel.selectedDateTime,
                              )}\n${DateFormat('KK:mm a').format(
                                eventModel.selectedDateTime,
                              )}',
                              textAlign: TextAlign.start,
                              style: const TextStyle(
                                color: AppThemeColor.pureBlackColor,
                                fontWeight: FontWeight.w900,
                                fontSize: Dimensions.fontSizeDefault,
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () async {
                            RouterClass.nextScreenNormal(
                              context,
                              SingleEventScreen(eventModel: eventModel),
                            );
                          },
                          child: Container(
                            width: 120,
                            decoration: BoxDecoration(
                              color: AppThemeColor.darkGreenColor,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: const Center(
                              child: Text(
                                'Details >>',
                                style: TextStyle(
                                  color: AppThemeColor.pureWhiteColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: Dimensions.fontSizeSmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
                const SizedBox(
                  height: 5,
                ),
                // GestureDetector(
                //   onTap: () async {
                //     await showModalBottomSheet(
                //       context: context,
                //       builder: (context) {
                //         return SelectProductPackage(
                //           currentProduct: d,
                //         );
                //       },
                //     ).then((value) {});
                //   },
                //   child: Container(
                //     // width: categoryImageWidth,
                //     decoration: BoxDecoration(
                //       color: AppThemeColor.darkGreenColor,
                //       borderRadius: BorderRadius.circular(7),
                //     ),
                //     padding: const EdgeInsets.symmetric(vertical: 6),
                //     child: Center(
                //       child: Text(
                //         AppLocale.addToCart.getString(context),
                //         style: const TextStyle(
                //           color: AppThemeColor.pureWhiteColor,
                //           fontWeight: FontWeight.w700,
                //           fontSize: Dimensions.fontSizeSmall,
                //         ),
                //       ),
                //     ),
                //   ),
                // ),
                // Expanded(
                //   child: _singleProductCartController(d: d),
                // ),
              ],
            ),
          ),
          if (eventModel.isFeatured)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppThemeColor.orangeColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
                child: const Text(
                  'FEATURED',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: Dimensions.fontSizeSmall,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
