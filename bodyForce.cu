#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "timer.h"
#include "check.h"

#define SOFTENING 1e-9f

/*
 * Each body contains x, y, and z coordinate positions,
 * as well as velocities in the x, y, and z directions.
 */

typedef struct { float x, y, z, vx, vy, vz; } Body;

/*
 * Do not modify this function. A constraint of this exercise is
 * that it remain a host function.
 */

void randomizeBodies(float *data, int n) {
  for (int i = 0; i < n; i++) {
    data[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
  }
}

/*
 * This function calculates the gravitational impact of all bodies in the system
 * on all others, but does not update their positions.
 */

 __global__ void bodyForce(Body *p, float dt, int n)
 {
   int ip = threadIdx.x + blockIdx.x * blockDim.x;
   int is = gridDim.x * blockDim.x;
   int jp = threadIdx.y + blockIdx.y * blockDim.y;
   int js = gridDim.y * blockDim.y;
   //int i_start = threadIdx.x + blockIdx.x * blockDim.x;
   //int i_stride = gridDim.x * blockDim.x;

   for (int i = ip; i < n; i += is)
   {
     float Fx = 0.0f; float Fy = 0.0f; float Fz = 0.0f;

     for (int j = jp; j < n; j += js)
     {
       float dx = p[j].x - p[i].x;
       float dy = p[j].y - p[i].y;
       float dz = p[j].z - p[i].z;
       float distSqr = dx*dx + dy*dy + dz*dz + SOFTENING;
       float invDist = rsqrtf(distSqr);
       float invDist3 = invDist * invDist * invDist;

       Fx += dx * invDist3; Fy += dy * invDist3; Fz += dz * invDist3;
     }

     p[i].vx += dt*Fx; p[i].vy += dt*Fy; p[i].vz += dt*Fz;
   }
 }

__global__ void intePosition (Body *p, float dt, int n)
{
  //int i = threadIdx.x + blockIdx.x * blockDim.x;
  int index = threadIdx.x + blockIdx.x * blockDim.x;
  int stride = gridDim.x * blockDim.x;

  for (int i = index; i < n; i += stride)
  {
    p[i].x += p[i].vx*dt;
    p[i].y += p[i].vy*dt;
    p[i].z += p[i].vz*dt;
  }
}


int main(const int argc, const char** argv) {

  int deviceId;
  int numberOfSMs;

  cudaGetDevice(&deviceId);
  cudaDeviceGetAttribute(&numberOfSMs, cudaDevAttrMultiProcessorCount, deviceId);
  printf("Device ID: %d\tNumber of SMs: %d\n", deviceId, numberOfSMs);

  /*
   * Do not change the value for `nBodies` here. If you would like to modify it,
   * pass values into the command line.
   */

  int nBodies = 2<<11;
  int salt = 0;
  if (argc > 1) nBodies = 2<<atoi(argv[1]);

  /*
   * This salt is for assessment reasons. Tampering with it will result in automatic failure.
   */

  if (argc > 2) salt = atoi(argv[2]);

  const float dt = 0.01f; // time step
  const int nIters = 10;  // simulation iterations

  int bytes = nBodies * sizeof(Body);
  float *buf;

  cudaMallocManaged(&buf, bytes);
  cudaMemPrefetchAsync(buf, bytes, cudaCpuDeviceId);

  Body *p = (Body*)buf;

  /*
   * As a constraint of this exercise, `randomizeBodies` must remain a host function.
   */

  randomizeBodies(buf, 6 * nBodies); // Init pos / vel data

  double totalTime = 0.0;

  //size_t threadsPerBlock = 64;
  //size_t numberOfBlocks = 32 * numberOfSMs;
  dim3 threadsPerBlock(64, 64, 1);
  dim3 numberOfBlocks(32*numberOfSMs, 32*numberOfSMs, 1);

  cudaError_t nBodyErr;
  cudaError_t asyncErr;


  /*
   * This simulation will run for 10 cycles of time, calculating gravitational
   * interaction amongst bodies, and adjusting their positions to reflect.
   */

  /*******************************************************************/
  // Do not modify these 2 lines of code.
  for (int iter = 0; iter < nIters; iter++) {
    StartTimer();
  /*******************************************************************/

  /*
   * You will likely wish to refactor the work being done in `bodyForce`,
   * as well as the work to integrate the positions.
   */
    cudaMemPrefetchAsync(buf, bytes, deviceId);

    cudaStream_t stream1, stream2;
    cudaStreamCreate(&stream1);
    cudaStreamCreate(&stream2);

    bodyForce<<<numberOfBlocks, threadsPerBlock, 0, stream1>>>(p, dt, nBodies); // compute interbody forces
    nBodyErr = cudaGetLastError();
    if(nBodyErr != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(nBodyErr));
    asyncErr = cudaDeviceSynchronize();
    if(asyncErr != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(asyncErr));

    intePosition<<<numberOfBlocks, threadsPerBlock, 0, stream2>>>(p, dt, nBodies); // integrate positio
    nBodyErr = cudaGetLastError();
    if(nBodyErr != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(nBodyErr));
    asyncErr = cudaDeviceSynchronize();
    if(asyncErr != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(asyncErr));

    cudaMemPrefetchAsync(buf, bytes, cudaCpuDeviceId);
    cudaStreamDestroy(stream1);
    cudaStreamDestroy(stream2);

  /*
   * This position integration cannot occur until this round of `bodyForce` has completed.
   * Also, the next round of `bodyForce` cannot begin until the integration is complete.
   */

  /*******************************************************************/
  // Do not modify the code in this section.
    const double tElapsed = GetTimer() / 1000.0;
    totalTime += tElapsed;
  }

  double avgTime = totalTime / (double)(nIters);
  float billionsOfOpsPerSecond = 1e-9 * nBodies * nBodies / avgTime;

#ifdef ASSESS
  checkPerformance(buf, billionsOfOpsPerSecond, salt);
#else
  checkAccuracy(buf, nBodies);
  printf("%d Bodies: average %0.3f Billion Interactions / second\n", nBodies, billionsOfOpsPerSecond);
  salt += 1;
#endif
  /*******************************************************************/

  /*
   * Feel free to modify code below.
   */

  cudaFree(buf);
}
