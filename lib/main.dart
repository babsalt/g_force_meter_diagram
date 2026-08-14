import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:g_force_meter/g_force_display.dart';
import 'package:g_force_meter/sensor_display.dart';
import 'package:g_force_meter/traction_circle.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:url_launcher/url_launcher.dart';

const double G = 9.80665;
final Uri url = Uri.parse("https://github.com/babsalt/g_force_meter_diagram");

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.pink),
      home: const MyHomePage(title: 'whats good beast'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  double gForceMagn = double.nan;
  double gForceX = double.nan;
  double gForceY = double.nan;
  double gForceZ = double.nan;
  bool noGravity = false;

  SharedPreferences? prefs;

  void updateGForce(List<double>? vec) {
    if (vec == null) return;
    double gForceTmp = 0;
    for (double val in vec) {
      gForceTmp += val * val;
    }
    gForceTmp = sqrt(gForceTmp);
    setState(() {
      gForceMagn = gForceTmp / G;
      gForceX = vec[0] / G;
      gForceY = vec[1] / G;
      gForceZ = vec[2] / G;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
          child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              GForceDisplay(gForceMagn, leftText: "Magnitude:"),
              Row(children: [
                Expanded(
                  child: GForceDisplay(gForceX,
                      leftText: "x:", fontSize: 40, padSign: true),
                ),
                Expanded(
                  child: GForceDisplay(gForceY,
                      leftText: "y:", fontSize: 40, padSign: true),
                ),
                Expanded(
                  child: GForceDisplay(gForceZ,
                      leftText: "z:", fontSize: 40, padSign: true),
                )
              ]),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("w/ gravity"),
                  Switch(
                      value: noGravity,
                      onChanged: (newValue) {
                        setState(() {
                          noGravity = newValue;
                        });
                        prefs?.setBool("noGravity", newValue);
                      }),
                  const Text("w/o gravity")
                ],
              ),
              SensorDisplay(
                  name: "Accelerometer",
                  eventStream: accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval),
                  eventToDoubles: (e) {
                    return <double>[e.x, e.y, e.z];
                  },
                  updateCallback: (vec) {
                    if (noGravity) return;
                    updateGForce(vec);
                  }),
              SensorDisplay(
                  name: "(w/o gravity)",
                  eventStream: userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval),
                  eventToDoubles: (e) {
                    return <double>[e.x, e.y, e.z];
                  },
                  updateCallback: (vec) {
                    if (!noGravity) return;
                    updateGForce(vec);
                  }),
              SensorDisplay(
                  name: "Gyroscope",
                  eventStream: gyroscopeEventStream(),
                  eventToDoubles: (e) {
                    return <double>[e.x, e.y, e.z];
                  }),
              SensorDisplay(
                  name: "Magnetometer",
                  eventStream: magnetometerEventStream(),
                  eventToDoubles: (e) {
                    return <double>[e.x, e.y, e.z];
                  }),
              const SizedBox(height: 16),
              TractionCircle(
                lateralG: gForceX.isNaN ? 0 : gForceX,
                longitudinalG: gForceY.isNaN ? 0 : gForceY,
              ),
            ],
          ),
        ),
      )),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          launchUrl(url, mode: LaunchMode.externalApplication);
        },
        tooltip: 'Increment',
        child: const Icon(SimpleIcons.github),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((value) {
      prefs = value;
      setState(() {
        noGravity = value.getBool("noGravity") ?? false;
      });
    });
  }
}
