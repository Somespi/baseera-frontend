import 'package:ar_flutter_plugin_flutterflow/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_session_manager.dart';
import 'package:basera/services/help_utilities.dart';
import 'package:flutter/material.dart';

void main() => runApp(ARroute());

class ARroute extends StatelessWidget {
  const ARroute({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ARroutePage(),
    );
  }
}

class ARroutePage extends StatefulWidget {
  const ARroutePage({super.key});

  @override
  State<ARroutePage> createState() => _ARroutePageState();
}

class _ARroutePageState extends State<ARroutePage> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ARView(
        onARViewCreated: onARViewCreated,
        planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
      ),
    );
  }
}

void onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager) {
  arSessionManager.onInitialize(
    showFeaturePoints: false,
    showPlanes: true,
    customPlaneTexturePath: "assets/triangle.png",
    showWorldOrigin: false,
  );
  arObjectManager.onInitialize();
}
