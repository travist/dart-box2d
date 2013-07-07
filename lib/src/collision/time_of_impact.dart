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
 * Class used for computing the time of impact. This class should not be
 * constructed usually, just retrieve from the SingletonPool.getTimeOfImpact().
 */

part of box2d;

class TimeOfImpact {
  static const int MAX_ITERATIONS = 1000;

  static int toiCalls;
  static int toiIters;
  static int toiMaxIters;
  static int toiRootIters;
  static int toiMaxRootIters;

  /** Pool variables */
  final SimplexCache cache;
  final DistanceInput distanceInput;
  final Transform xfA;
  final Transform xfB;
  final DistanceOutput distanceOutput;
  final SeparationFunction fcn;
  final List<int> indexes;
  final Sweep sweepA;
  final Sweep sweepB;

  DefaultWorldPool pool;

  TimeOfImpact._construct(DefaultWorldPool argPool) :
    pool = argPool,
    cache = new SimplexCache(),
    distanceInput = new DistanceInput(),
    xfA = new Transform(),
    xfB = new Transform(),
    distanceOutput = new DistanceOutput(),
    fcn = new SeparationFunction(),
    indexes = new List<int>(2),
    sweepA = new Sweep(),
    sweepB = new Sweep() {
    indexes[0] = 0;
    indexes[1] = 0;
    toiCalls = 0;
    toiIters = 0;
    toiMaxIters = 0;
    toiRootIters = 0;
    toiMaxRootIters = 0;
  }

  /**
   * Compute the upper bound on time before two shapes penetrate. Time is
   * represented as a fraction between [0,tMax]. This uses a swept separating
   * axis and may miss some intermediate, non-tunneling collision. If you
   * change the time interval, you should call this function again.
   * Note: use Distance to compute the contact point and normal at the time
   * of impact.
   */
  void timeOfImpact(TimeOfImpactOutput output, TimeOfImpactInput input) {
    // CCD via the local separating axis method. This seeks progression
    // by computing the largest time at which separation is maintained.
    ++toiCalls;

    output.state = TimeOfImpactOutputState.UNKNOWN;
    output.t = input.tMax;

    DistanceProxy proxyA = input.proxyA;
    DistanceProxy proxyB = input.proxyB;

    sweepA.setFrom(input.sweepA);
    sweepB.setFrom(input.sweepB);

    // Large rotations can make the root finder fail, so we normalize the
    // sweep angles.
    sweepA.normalize();
    sweepB.normalize();

    double tMax = input.tMax;

    double totalRadius = proxyA.radius + proxyB.radius;
    double target = Math.max(Settings.LINEAR_SLOP,
        totalRadius - 3.0 * Settings.LINEAR_SLOP);
    double tolerance = 0.25 * Settings.LINEAR_SLOP;

    assert (target > tolerance);

    double t1 = 0.0;
    int iter = 0;

    cache.count = 0;
    distanceInput.proxyA = input.proxyA;
    distanceInput.proxyB = input.proxyB;
    distanceInput.useRadii = false;

    // The outer loop progressively attempts to compute new separating axes.
    // This loop terminates when an axis is repeated (no progress is made).
    while (true) {
      sweepA.getTransform(xfA, t1);
      sweepB.getTransform(xfB, t1);
      // Get the distance between shapes. We can also use the results
      // to get a separating axis
      distanceInput.transformA = xfA;
      distanceInput.transformB = xfB;
      pool.distance.distance(distanceOutput, cache, distanceInput);

      // If the shapes are overlapped, we give up on continuous collision.
      if (distanceOutput.distance <= 0) {
        // Failure!
        output.state = TimeOfImpactOutputState.OVERLAPPED;
        output.t = 0;
        break;
      }

      if (distanceOutput.distance < target + tolerance) {
        // Victory!
        output.state = TimeOfImpactOutputState.TOUCHING;
        output.t = t1;
        break;
      }

      // Initialize the separating axis.
      fcn.initialize(cache, proxyA, sweepA, proxyB, sweepB, t1);

      // Compute the TimeOfImpact on the separating axis. We do this by successively
      // resolving the deepest point. This loop is bounded by the number of
      // vertices.
      bool done = false;
      num t2 = tMax;
      int pushBackIter = 0;
      while (true) {

        // Find the deepest point at t2. Store the witness point indices.
        num s2 = fcn.findMinSeparation(indexes, t2);
        // Is the configuration separated?
        if (s2 > target + tolerance) {
          // Victory!
          output.state = TimeOfImpactOutputState.SEPARATED;
          output.t = tMax;
          done = true;
          break;
        }

        // Has the separation reached tolerance?
        if (s2 > target - tolerance) {
          // Advance the sweeps
          t1 = t2;
          break;
        }

        // Compute the initial separation of the witness points.
        num s1 = fcn.evaluate(indexes[0], indexes[1], t1);
        // Check for initial overlap. This might happen if the root finder
        // runs out of iterations.
        if (s1 < target - tolerance) {
          output.state = TimeOfImpactOutputState.FAILED;
          output.t = t1;
          done = true;
          break;
        }

        // Check for touching
        if (s1 <= target + tolerance) {
          // Victory! t1 should hold the TimeOfImpact (could be 0.0).
          output.state = TimeOfImpactOutputState.TOUCHING;
          output.t = t1;
          done = true;
          break;
        }

        // Compute 1D root of: f(x) - target = 0
        int rootIterCount = 0;
        num a1 = t1, a2 = t2;
        while (true) {
          // Use a mix of the secant rule and bisection.
          num t;
          if ((rootIterCount & 1) == 1) {
            // Secant rule to improve convergence.
            t = a1 + (target - s1) * (a2 - a1) / (s2 - s1);
          } else {
            // Bisection to guarantee progress.
            t = 0.5 * (a1 + a2);
          }

          num s = fcn.evaluate(indexes[0], indexes[1], t);

          if ((s - target).abs() < tolerance) {
            // t2 holds a tentative value for t1
            t2 = t;
            break;
          }

          // Ensure we continue to bracket the root.
          if (s > target) {
            a1 = t;
            s1 = s;
          } else {
            a2 = t;
            s2 = s;
          }

          ++rootIterCount;
          ++toiRootIters;

          // djm: whats with this? put in settings?
          if (rootIterCount == 50) {
            break;
          }
        }

        toiMaxRootIters = Math.max(toiMaxRootIters, rootIterCount);

        ++pushBackIter;

        if (pushBackIter == Settings.MAX_POLYGON_VERTICES) {
          break;
        }
      }

      ++iter;
      ++toiIters;

      if (done)
        break;

      if (iter == MAX_ITERATIONS) {
        // Root finder got stuck. Semi-victory.
        output.state = TimeOfImpactOutputState.FAILED;
        output.t = t1;
        break;
      }
    }

    toiMaxIters = Math.max(toiMaxIters, iter);
  }
}

class SeparationFunction {
  DistanceProxy proxyA;
  DistanceProxy proxyB;
  int type;
  final Vector2 localPoint;
  final Vector2 axis;
  Sweep sweepA;
  Sweep sweepB;

  /** Pooling */
  final Vector2 localPointA;
  final Vector2 localPointB;
  final Vector2 pointA;
  final Vector2 pointB;
  final Vector2 localPointA1;
  final Vector2 localPointA2;
  final Vector2 normal;
  final Vector2 localPointB1;
  final Vector2 localPointB2;
  final Vector2 axisA;
  final Vector2 axisB;
  final Vector2 temp;
  final Transform xfa;
  final Transform xfb;

  SeparationFunction() :
    proxyA = new DistanceProxy(),
    proxyB = new DistanceProxy(),
    type = SeparationType.POINTS,
    localPoint = new Vector2.zero(),
    axis = new Vector2.zero(),
    sweepA = new Sweep(),
    sweepB = new Sweep(),
    localPointA = new Vector2.zero(),
    localPointB = new Vector2.zero(),
    pointA = new Vector2.zero(),
    pointB = new Vector2.zero(),
    localPointA1 = new Vector2.zero(),
    localPointA2 = new Vector2.zero(),
    normal = new Vector2.zero(),
    localPointB1 = new Vector2.zero(),
    localPointB2 = new Vector2.zero(),
    temp = new Vector2.zero(),
    xfa = new Transform(),
    xfb = new Transform(),
    axisA = new Vector2.zero(),
    axisB = new Vector2.zero();

  num initialize(SimplexCache cache, DistanceProxy argProxyA, Sweep
      argSweepA, DistanceProxy argProxyB, Sweep argSweepB, num t1) {
    proxyA = argProxyA;
    proxyB = argProxyB;
    int count = cache.count;
    assert (0 < count && count < 3);

    sweepA = argSweepA;
    sweepB = argSweepB;

    sweepA.getTransform(xfa, t1);
    sweepB.getTransform(xfb, t1);

    if (count == 1) {
      type = SeparationType.POINTS;
      localPointA.setFrom(proxyA.vertices[cache.indexA[0]]);
      localPointB.setFrom(proxyB.vertices[cache.indexB[0]]);
      Transform.mulToOut(xfa, localPointA, pointA);
      Transform.mulToOut(xfb, localPointB, pointB);
      axis.setFrom(pointB).sub(pointA);
      num s = axis.normalizeLength();
      return s;
    } else if (cache.indexA[0] == cache.indexA[1]) {
      // Two points on B and one on A.
      type = SeparationType.FACE_B;

      localPointB1.setFrom(proxyB.vertices[cache.indexB[0]]);
      localPointB2.setFrom(proxyB.vertices[cache.indexB[1]]);

      temp.setFrom(localPointB2).sub(localPointB1);
      Vector2_crossVectorAndNumToOut(temp, 1.0, axis);
      axis.normalize();

      xfb.rotation.transformed(axis, normal);

      localPoint.setFrom(localPointB1);
      localPoint.add(localPointB2);
      localPoint.scale(.5);
      Transform.mulToOut(xfb, localPoint, pointB);

      localPointA.setFrom(proxyA.vertices[cache.indexA[0]]);
      Transform.mulToOut(xfa, localPointA, pointA);

      temp.setFrom(pointA);
      temp.sub(pointB);
      num s = temp.dot(normal);
      if (s < 0.0) {
        axis.negate();
        s = -s;
      }

      return s;
    } else {
      // Two points on A and one or two points on B.
      type = SeparationType.FACE_A;

      localPointA1.setFrom(proxyA.vertices[cache.indexA[0]]);
      localPointA2.setFrom(proxyA.vertices[cache.indexA[1]]);

      temp.setFrom(localPointA2);
      temp.sub(localPointA1);
      Vector2_crossVectorAndNumToOut(temp, 1.0, axis);
      axis.normalize();

      xfa.rotation.transformed(axis, normal);

      localPoint.setFrom(localPointA1);
      localPoint.add(localPointA2);
      localPoint.scale(.5);
      Transform.mulToOut(xfa, localPoint, pointA);

      localPointB.setFrom(proxyB.vertices[cache.indexB[0]]);
      Transform.mulToOut(xfb, localPointB, pointB);

      temp.setFrom(pointB);
      temp.sub(pointA);
      num s = temp.dot(normal);
      if (s < 0.0) {
        axis.negate();
        s = -s;
      }
      return s;
    }
  }

  num findMinSeparation(List<int> indexes, num t) {
    sweepA.getTransform(xfa, t);
    sweepB.getTransform(xfb, t);

    switch (type) {
      case SeparationType.POINTS:
        Matrix2_mulTransMatrixAndVectorToOut(xfa.rotation, axis, axisA);
        Matrix2_mulTransMatrixAndVectorToOut(xfb.rotation, axis.negate(),
            axisB);
        axis.negate();

        indexes[0] = proxyA.getSupport(axisA);
        indexes[1] = proxyB.getSupport(axisB);

        localPointA.setFrom(proxyA.vertices[indexes[0]]);
        localPointB.setFrom(proxyB.vertices[indexes[1]]);

        Transform.mulToOut(xfa, localPointA, pointA);
        Transform.mulToOut(xfb, localPointB, pointB);

        num separation = pointB.sub(pointA).dot(axis);
        return separation;

      case SeparationType.FACE_A:
        xfa.rotation.transformed(axis, normal);
        Transform.mulToOut(xfa, localPoint, pointA);

        normal.negate();
        Matrix2_mulTransMatrixAndVectorToOut(xfb.rotation, normal, axisB);
        normal.negate();

        indexes[0] = -1;
        indexes[1] = proxyB.getSupport(axisB);

        localPointB.setFrom(proxyB.vertices[indexes[1]]);
        Transform.mulToOut(xfb, localPointB, pointB);

        num separation = pointB.sub(pointA).dot(normal);
        return separation;

      case SeparationType.FACE_B:
        xfb.rotation.transformed(axis, normal);
        Transform.mulToOut(xfb, localPoint, pointB);

        Matrix2_mulTransMatrixAndVectorToOut(xfa.rotation,
            normal.negate(), axisA);
        normal.negate();

        indexes[1] = -1;
        indexes[0] = proxyA.getSupport(axisA);

        localPointA.setFrom(proxyA.vertices[indexes[0]]);
        Transform.mulToOut(xfa, localPointA, pointA);

        num separation = pointA.sub(pointB).dot(normal);
        return separation;

      default:
        assert (false);
        indexes[0] = -1;
        indexes[1] = -1;
        return 0;
    }
  }

  num evaluate(int indexA, int indexB, num t) {
    sweepA.getTransform(xfa, t);
    sweepB.getTransform(xfb, t);

    switch (type) {
      case SeparationType.POINTS:
        Matrix2_mulTransMatrixAndVectorToOut(xfa.rotation, axis, axisA);
        Matrix2_mulTransMatrixAndVectorToOut(xfb.rotation, axis.negate(),
            axisB);
        axis.negate();

        localPointA.setFrom(proxyA.vertices[indexA]);
        localPointB.setFrom(proxyB.vertices[indexB]);

        Transform.mulToOut(xfa, localPointA, pointA);
        Transform.mulToOut(xfb, localPointB, pointB);

        num separation = pointB.sub(pointA).dot(axis);
        return separation;

      case SeparationType.FACE_A:
        xfa.rotation.transformed(axis, normal);
        Transform.mulToOut(xfa, localPoint, pointA);

        normal.negate();
        Matrix2_mulTransMatrixAndVectorToOut(xfb.rotation, normal, axisB);
        normal.negate();

        localPointB.setFrom(proxyB.vertices[indexB]);
        Transform.mulToOut(xfb, localPointB, pointB);
        num separation = pointB.sub(pointA).dot(normal);
        return separation;

      case SeparationType.FACE_B:
        xfb.rotation.transformed(axis, normal);
        Transform.mulToOut(xfb, localPoint, pointB);

        Matrix2_mulTransMatrixAndVectorToOut(xfa.rotation,
            normal.negate(), axisA);
        normal.negate();

        localPointA.setFrom(proxyA.vertices[indexA]);
        Transform.mulToOut(xfa, localPointA, pointA);

        num separation = pointA.sub(pointB).dot(normal);
        return separation;

      default:
        assert (false);
        return 0;
    }
  }
}

/**
 * Input parameters for TimeOfImpact.
 */
class TimeOfImpactInput {
  final DistanceProxy proxyA;
  final DistanceProxy proxyB;
  final Sweep sweepA;
  final Sweep sweepB;

  /**
   * defines sweep interval [0, tMax]
   */
  num tMax;

  TimeOfImpactInput() :
    proxyA = new DistanceProxy(),
    proxyB = new DistanceProxy(),
    sweepA = new Sweep(),
    sweepB = new Sweep(),
    tMax = 0 { }
}

/** Enum for TimeOfImpact output. */
class TimeOfImpactOutputState {
  static const int UNKNOWN = 0;
  static const int FAILED = 1;
  static const int OVERLAPPED = 2;
  static const int TOUCHING = 3;
  static const int SEPARATED = 4;
}

/**
 * Output parameters for TimeOfImpact
 */
class TimeOfImpactOutput {
  int state;
  num t;

  TimeOfImpactOutput() :
    state = TimeOfImpactOutputState.UNKNOWN,
    t = 0 { }
}

class SeparationType {
  static const int POINTS = 0;
  static const int FACE_A = 1;
  static const int FACE_B = 2;
}
