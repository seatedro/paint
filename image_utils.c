// image_utils.c
#include "image_utils.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))

// Replace the existing calculate_resize_dims with this
static void get_preprocess_shape(int old_h, int old_w, int target_length,
                                 int *new_h, int *new_w, float *scale) {
  // Scale based on longest side
  *scale = (float)target_length / (float)MAX(old_h, old_w);

  // Calculate new dimensions maintaining aspect ratio
  float new_h_float = old_h * *scale;
  float new_w_float = old_w * *scale;

  // Round to nearest integer
  *new_h = (int)(new_h_float + 0.5f);
  *new_w = (int)(new_w_float + 0.5f);

  printf("Resizing from %dx%d to %dx%d (scale: %.3f)\n", old_w, old_h, *new_w,
         *new_h, *scale);
}

// Update preprocess_image function
float *preprocess_image(const ImageData *input_image, const int target_length,
                        int64_t *output_shape) {
  if (!input_image || !input_image->data || !output_shape) {
    printf("Invalid input parameters in preprocess_image\n");
    return NULL;
  }

  // Calculate resize dimensions
  int resized_height, resized_width;
  float scale;
  get_preprocess_shape(input_image->height, input_image->width, target_length,
                       &resized_height, &resized_width, &scale);

  // Allocate for padded square image (1024x1024)
  size_t tensor_size = 1 * 3 * target_length * target_length;
  float *preprocessed = (float *)calloc(tensor_size, sizeof(float));
  if (!preprocessed) {
    printf("Failed to allocate memory for preprocessed image\n");
    return NULL;
  }

  int offset_x = (target_length - resized_width) / 2;
  int offset_y = (target_length - resized_height) / 2;

  // Normalization constants
  const float means[3] = {123.675f, 116.28f, 103.53f};
  const float stds[3] = {58.395f, 57.12f, 57.375f};

  // Perform resize with bilinear interpolation
  for (int y = 0; y < resized_height; y++) {
    for (int x = 0; x < resized_width; x++) {
      // Calculate source position with proper scaling
      float src_x = x / scale;
      float src_y = y / scale;

      // Bilinear interpolation
      int x0 = (int)src_x;
      int y0 = (int)src_y;
      int x1 = MIN(x0 + 1, input_image->width - 1);
      int y1 = MIN(y0 + 1, input_image->height - 1);

      float wx = src_x - x0;
      float wy = src_y - y0;

      // For each channel
      for (int c = 0; c < 3; c++) {
        float p00 = input_image->data[(y0 * input_image->width + x0) * 3 + c];
        float p01 = input_image->data[(y0 * input_image->width + x1) * 3 + c];
        float p10 = input_image->data[(y1 * input_image->width + x0) * 3 + c];
        float p11 = input_image->data[(y1 * input_image->width + x1) * 3 + c];

        // Bilinear interpolation formula
        float pixel = (1 - wx) * (1 - wy) * p00 + wx * (1 - wy) * p01 +
                      (1 - wx) * wy * p10 + wx * wy * p11;

        // Store in NCHW format with normalization
        // Position in padded output
        int dst_x = x + offset_x;
        int dst_y = y + offset_y;
        int dst_idx =
            c * target_length * target_length + dst_y * target_length + dst_x;

        // Normalize properly
        float pixel_value = pixel / 255.0f;
        preprocessed[dst_idx] = (pixel_value * 255.0f - means[c]) / stds[c];
      }
    }
  }

  // Set output shape
  output_shape[0] = 1;             // batch size
  output_shape[1] = 3;             // channels
  output_shape[2] = target_length; // height
  output_shape[3] = target_length; // width

  printf(
      "Preprocessing complete. Output tensor shape: [%lld, %lld, %lld, %lld]\n",
      output_shape[0], output_shape[1], output_shape[2], output_shape[3]);

  return preprocessed;
}

void transform_coords(float *coords, int num_points, int orig_width,
                      int orig_height, const int target_size, int *out_width,
                      int *out_height) {
  // Calculate resize dimensions maintaining aspect ratio
  int resized_width, resized_height;
  float scale;
  get_preprocess_shape(orig_width, orig_height, target_size, &resized_width,
                       &resized_height, &scale);

  // Transform each point
  for (int i = 0; i < num_points * 2; i += 2) {
    coords[i] = coords[i] * ((float)resized_width / orig_width);
    coords[i + 1] = coords[i + 1] * ((float)resized_height / orig_height);
  }

  if (out_width)
    *out_width = resized_width;
  if (out_height)
    *out_height = resized_height;

  printf("Transformed coordinates with scale %.3f (%dx%d -> %dx%d)\n", scale,
         orig_width, orig_height, resized_width, resized_height);
}
