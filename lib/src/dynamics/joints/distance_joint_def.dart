// Copyright 2012 Google Inc. All Rights Reserved.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Distance joint definition. This requires defining an
 * anchor point on both bodies and the non-zero length of the
 * distance joint. The definition uses local anchor points
 * so that the initial configuration can violate the constraint
 * slightly. This helps when saving and loading a game.
 * Warning: Do not use a zero or short length.
 */

part of box2d;

class DistanceJointDef extends JointDef {
  /** The local anchor point relative to body1's origin. */
  final Vector2 localAnchorA = new Vector2.zero();

  /** The local anchor point relative to body2's origin. */
  final Vector2 localAnchorB = new Vector2.zero();

  /** The equilibrium length between the anchor points. */
  double length = 1.0;

  /**
   * The mass-spring-damper frequency in Hertz.
   */
  double frequencyHz = 0.0;

  /**
   * The damping ratio. 0 = no damping, 1 = critical damping.
   */
  double dampingRatio = 0.0;

  DistanceJointDef() : super() {
    type = JointType.DISTANCE;
  }

  /**
   * Initialize the bodies, anchors, and length using the world
   * anchors.
   * b1: First body
   * b2: Second body
   * anchor1: World anchor on first body
   * anchor2: World anchor on second body
   */
  void initialize(Body b1, Body b2, Vector2 anchor1, Vector2 anchor2) {
    bodyA = b1;
    bodyB = b2;
    localAnchorA.setFrom(bodyA.getLocalPoint(anchor1));
    localAnchorB.setFrom(bodyB.getLocalPoint(anchor2));
    Vector2 d = new Vector2.copy(anchor2);
    d.sub(anchor1);
    length = d.length;
  }
}
