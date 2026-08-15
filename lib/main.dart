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
import 'package:refresh_rate/refresh_rate.dart';

const double G = 9.80665;
final Uri url = Uri.parse("https://github.com/babsalt/g_force_meter_diagram");

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RefreshRate.enable();
  // print(RefreshRate.info);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MyHomePage(title: 'G-Force'),
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
  double gForceMagn = 0.0;
  double gForceX = 0.0;
  double gForceY = 0.0;
  double gForceZ = 0.0;
  bool noGravity = false;
  var trail = List.generate(150, (_) => [0.0, 0.0, 0.0]);
  int stack = 0;
  var offsetX = 0.0;
  var offsetY = 0.0;
  var offsetZ = 0.0;

  SharedPreferences? prefs;

  final double alpha = 0.5;

  void updateGForce(List<double>? vec) {
    if (vec == null) return;

    double rawX = vec[0] / G;
    double rawY = vec[1] / G;
    double rawZ = vec[2] / G;

    if (!noGravity) {
      rawX -= offsetX;
      rawY -= offsetY;
      rawZ -= offsetZ;
    }

    setState(() {
      //(alpha * New) + ((1 - alpha) * Old)
      gForceX = (alpha * rawX) + ((1.0 - alpha) * gForceX);
      gForceY = (alpha * rawY) + ((1.0 - alpha) * gForceY);
      gForceZ = -(alpha * rawZ) + ((1.0 - alpha) * gForceZ);

      gForceMagn = sqrt((gForceX * gForceX) + (gForceY * gForceY) + (gForceZ * gForceZ));

      trail[stack] = [gForceX, gForceY, gForceZ];
      stack = (stack + 1) % 150;
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
              GForceDisplay(gForceMagn, leftText: "Magnitude:", fontSize: 60),
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
                  const Text("w/o gravity (less responsive)")
                ],
              ),
              SensorDisplay(
                  name: "Accelerometer",
                  eventStream: accelerometerEventStream(samplingPeriod: SensorInterval.lowInterval),
                  eventToDoubles: (e) {
                    return <double>[e.x, e.y, e.z];
                  },
                  updateCallback: (vec) {
                    if (noGravity) return;
                    updateGForce(vec);
                  }),
              SensorDisplay(
                  name: "(w/o gravity)",
                  eventStream: userAccelerometerEventStream(samplingPeriod: SensorInterval.lowInterval),
                  eventToDoubles: (e) {
                    return <double>[e.x, e.y, e.z];
                  },
                  updateCallback: (vec) {
                    if (!noGravity) return;
                    updateGForce(vec);
                  }),
              // SensorDisplay(
              //     name: "Gyroscope",
              //     eventStream: gyroscopeEventStream(),
              //     eventToDoubles: (e) {
              //       return <double>[e.x, e.y, e.z];
              //     }),
              // SensorDisplay(
              //     name: "Magnetometer",
              //     eventStream: magnetometerEventStream(),
              //     eventToDoubles: (e) {
              //       return <double>[e.x, e.y, e.z];
              //     }),
              FractionallySizedBox(
                widthFactor: 0.95,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: TractionCircle(
                    lateralG: gForceX.isNaN ? 0 : gForceX,
                    longitudinalG: gForceY.isNaN ? 0 : gForceZ,
                    trail: trail,
                    trailStart: stack,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    offsetX = offsetX + (trail[(stack - 1 + 150) % 150][0] + trail[(stack - 2 + 150) % 150][0] + trail[(stack - 3 + 150) % 150][0]) / 3.0;
                    offsetY = offsetY + (trail[(stack - 1 + 150) % 150][1] + trail[(stack - 2 + 150) % 150][1] + trail[(stack - 3 + 150) % 150][1]) / 3.0;
                    offsetZ = offsetZ + (trail[(stack - 1 + 150) % 150][2] + trail[(stack - 2 + 150) % 150][2] + trail[(stack - 3 + 150) % 150][2]) / 3.0;
                  });
                },
                child: const Text('Calibrate'),
              )
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
