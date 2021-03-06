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
 * This joint is commonly used to simulate a soft body with a constant volume.
 * A constant volume joint can only be created with three or more bodies. The
 * area within a grouping of constant volume joints is kept constant, such that
 * the compression of one part of the area will be offset by the expansion of
 * other parts.
 */

part of box2d;

class ConstantVolumeJoint extends Joint {
  List<Body> bodies;
  List<double> targetLengths;
  double targetVolume;

  List<Vector2> normals;

  TimeStep step;

  double _impulse = 0.0;

  World _world;

  List<DistanceJoint> distanceJoints;

  double frequencyHz;
  double dampingRatio;

  ConstantVolumeJoint(this._world, ConstantVolumeJointDef def) : super(def) {
    if (def.bodies.length <= 2) {
      throw new ArgumentError(
          "You cannot create a constant volume joint with less than three "
          "bodies.");
    }

    // Create a fixed size array with a capacity equal to the number of elements
    // in the growable array in the definition.
    bodies = new List.from(def.bodies);

    targetLengths = new List<double>(bodies.length);
    for (int i = 0; i < targetLengths.length; ++i) {
      final int next = (i == targetLengths.length - 1) ? 0 : i + 1;
      Vector2 temp = new Vector2.copy(bodies[i].worldCenter);
      temp.sub(bodies[next].worldCenter);
      num dist = temp.length;
      targetLengths[i] = dist;
    }
    targetVolume = area;

    if (def.joints != null && def.joints.length != def.bodies.length) {
      throw new ArgumentError(
          "Incorrect joint definition.  Joints have to correspond to "
          "the bodies");
    }

    if (def.joints == null) {
      final djd = new DistanceJointDef();
      distanceJoints = new List<DistanceJoint>(bodies.length);
      for (int i = 0; i < targetLengths.length; ++i) {
        final int next = (i == targetLengths.length - 1) ? 0 : i + 1;
        djd.frequencyHz = def.frequencyHz;
        djd.dampingRatio = def.dampingRatio;
        djd.initialize(bodies[i], bodies[next], bodies[i].worldCenter,
            bodies[next].worldCenter);
        distanceJoints[i] = _world.createJoint(djd);
      }
    } else {
      distanceJoints = new List<DistanceJoint>(def.joints.length);
      distanceJoints.setRange(0, def.joints.length, def.joints);
    }

    frequencyHz = def.frequencyHz;
    dampingRatio = def.dampingRatio;

    normals = new List<Vector2>.generate(bodies.length, (i) => new Vector2.zero());

    this.bodyA = bodies[0];
    this.bodyB = bodies[1];
    this.collideConnected = false;
  }

  void inflate(num factor) {
    targetVolume *= factor;
  }

  void destructor() {
    for (int i = 0; i < distanceJoints.length; ++i) {
      _world.destroyJoint(distanceJoints[i]);
    }
  }

  num get area {
    num result = 0.0;
    result += bodies[bodies.length - 1].worldCenter.x * bodies[0].worldCenter.y
        - bodies[0].worldCenter.x * bodies[bodies.length - 1].worldCenter.y;
    for (int i = 0; i < bodies.length - 1; ++i) {
      result += bodies[i].worldCenter.x * bodies[i + 1].worldCenter.y
          - bodies[i + 1].worldCenter.x * bodies[i].worldCenter.y;
    }
    result *= .5;
    return result;
  }

  /** Apply the position correction to the particles. */
  bool constrainEdges(TimeStep argStep) {
    num perimeter = 0.0;
    for (int i = 0; i < bodies.length; ++i) {
      final int next = (i == bodies.length - 1) ? 0 : i + 1;
      num dx = bodies[next].worldCenter.x - bodies[i].worldCenter.x;
      num dy = bodies[next].worldCenter.y - bodies[i].worldCenter.y;
      num dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < Settings.EPSILON) {
        dist = 1.0;
      }
      normals[i].x = dy / dist;
      normals[i].y = -dx / dist;
      perimeter += dist;
    }

    final delta = new Vector2.zero();

    num deltaArea = targetVolume - area;
    num toExtrude = 0.5 * deltaArea / perimeter; // relaxationFactor
    bool done = true;
    for (int i = 0; i < bodies.length; ++i) {
      final int next = (i == bodies.length - 1) ? 0 : i + 1;
      delta.setValues(toExtrude * (normals[i].x + normals[next].x), toExtrude
          * (normals[i].y + normals[next].y));
      num norm = delta.length;
      if (norm > Settings.MAX_LINEAR_CORRECTION) {
        delta.scale(Settings.MAX_LINEAR_CORRECTION / norm);
      }
      if (norm > Settings.LINEAR_SLOP) {
        done = false;
      }
      bodies[next].sweep.center.x += delta.x;
      bodies[next].sweep.center.y += delta.y;
      bodies[next].synchronizeTransform();
    }

    return done;
  }

  void initVelocityConstraints(TimeStep argStep) {
    step = argStep;

    final d = new List<Vector2>.generate(bodies.length, (i) => new Vector2.zero());

    for (int i = 0; i < bodies.length; ++i) {
      final int prev = (i == 0) ? bodies.length - 1 : i - 1;
      final int next = (i == bodies.length - 1) ? 0 : i + 1;
      d[i].setFrom(bodies[next].worldCenter);
      d[i].sub(bodies[prev].worldCenter);
    }

    if (step.warmStarting) {
      _impulse *= step.dtRatio;
      for (int i = 0; i < bodies.length; ++i) {
        bodies[i].linearVelocity.x += bodies[i].invMass * d[i].y *
            .5 * _impulse;
        bodies[i].linearVelocity.y += bodies[i].invMass * -d[i].x *
            .5 * _impulse;
      }
    } else {
      _impulse = 0.0;
    }
  }

  /**
   * Solves for the impact of this joint on the positions of the connected
   * bodies. Implements abstract method in [Joint].
   */
  bool solvePositionConstraints(num baumgarte) {
    return constrainEdges(step);
  }

  /**
   * Solves for the impact of this joint on the velocities of the connected
   * bodies. Implements abstract method in [Joint].
   */
  void solveVelocityConstraints(TimeStep argStep) {
    num crossMassSum = 0.0;
    num dotMassSum = 0.0;

    final d = new List<Vector2>.generate(bodies.length, (i) => new Vector2.zero());

    for (int i = 0; i < bodies.length; ++i) {
      final int prev = (i == 0) ? bodies.length - 1 : i - 1;
      final int next = (i == bodies.length - 1) ? 0 : i + 1;
      d[i].setFrom(bodies[next].worldCenter);
      d[i].sub(bodies[prev].worldCenter);
      dotMassSum += (d[i].length2) / bodies[i].mass;
      crossMassSum += bodies[i].linearVelocity.cross(d[i]);
    }
    num lambda = -2.0 * crossMassSum / dotMassSum;
    _impulse += lambda;
    for (int i = 0; i < bodies.length; ++i) {
      bodies[i].linearVelocity.x += bodies[i].invMass * d[i].y * .5 * lambda;
      bodies[i].linearVelocity.y += bodies[i].invMass * -d[i].x * .5 * lambda;
    }
  }

  void getAnchorA(Vector2 argOut) { throw new UnimplementedError(); }

  void getAnchorB(Vector2 argOut) { throw new UnimplementedError(); }

  void getReactionForce(num inv_dt, Vector2 argOut) { throw new UnimplementedError(); }

  num getReactionTorque(num inv_dt) { throw new UnimplementedError(); }
}
