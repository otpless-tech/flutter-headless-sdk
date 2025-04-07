import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:otpless_headless_flutter/otpless_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _dataResponse = 'Unknown';
  final _otplessHeadlessPlugin = Otpless();
  var loaderVisibility = true;
  bool isSimStateListenerAttached = false;
  final TextEditingController phoneController =
      TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  String channel = "WHATSAPP";

  String phone = '';
  String email = '';
  String otp = '';

  String deliveryChannel = '';
  String otpLength = "";
  String expiry = "";

  String appId = "od6f3sjgcp93605da5om";

  @override
  void initState() {
    super.initState();
      _otplessHeadlessPlugin.initialize(appId, timeout: 23);
      _otplessHeadlessPlugin.setResponseCallback(onHeadlessResult);
  }

  Future<void> startHeadlessForPhoneAndEmail() async {

    Map<String, dynamic> arg = {};
    if (phone.isNotEmpty) {
      arg["phone"] = phone;
      arg["countryCode"] = "91";
    } else if (email.isNotEmpty) {
      arg["email"] = email;
    } else {
      arg["channelType"] = channel.toUpperCase();
    }

    // arg["tid"] = "";

    if (otp.isNotEmpty) {
      arg["otp"] = otp;
    }
    // adding delivery channel, otp length and expiry
    if (deliveryChannel.isNotEmpty) {
      arg["deliveryChannel"] = deliveryChannel;
    }
    if (otpLength.isNotEmpty) {
      arg["otpLength"] = otpLength;
    }
    if (expiry.isNotEmpty) {
      arg["expiry"] = expiry;
    }

    _otplessHeadlessPlugin.start(onHeadlessResult, arg);
  }

  void onHeadlessResult(dynamic result) {
    setState(() {
      _dataResponse = jsonEncode(result);
      _otplessHeadlessPlugin.commitResponse(result);
      String responseType = result["responseType"];
      if (responseType == "OTP_AUTO_READ") {
        String _otp = result["response"]["otp"];
        otpController.text = _otp;
        otp = _otp;
      }
    });
  }

  @override
  void dispose() {
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
            child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0), // Adjusted margin
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment
                    .stretch, // Makes the buttons fill the width
                children: [
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    onChanged: (value) {
                      setState(() {
                        phone = value;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Enter Phone',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) {
                      setState(() {
                        email = value;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Email ID',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) {
                      setState(() {
                        otp = value;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Enter your OTP here',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        channel = value;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Enter channel for OAuth',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) {
                            deliveryChannel = value;
                          },
                          decoration: const InputDecoration(hintText: "Delivery Channel"),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: TextField(
                          onChanged: (value) {
                            otpLength = value;
                          },
                          decoration: const InputDecoration(hintText: "OTP length"),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: TextField(
                          onChanged: (value) {
                            expiry = value;
                          },
                          decoration: const InputDecoration(hintText: "Expiry"),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // adding delivery channel
                  CupertinoButton.filled(
                    onPressed: startHeadlessForPhoneAndEmail,
                    child: const Text("Start"),
                  ),
                  const SizedBox(height: 16),
                  // response view
                  Text(
                    _dataResponse,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        )),
      ),
    );
  }
}
