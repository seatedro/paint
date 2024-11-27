// image_utils.h
#ifndef IMAGE_UTILS_H
#define IMAGE_UTILS_H

#include <stdint.h>
#include "onnx_bridge.h"

// Preprocess image for MobileSAM model
// input_image: source image data
// target_size: maximum size for the longest dimension
// output_shape: array to store the output tensor shape (must be size 4)
// Returns: preprocessed image data in NCHW format, or NULL on error
float* preprocess_image(const ImageData* input_image, 
                       const int target_size,
                       int64_t* output_shape);

void transform_coords(float* coords, int num_points,
                     int orig_width, int orig_height, 
                     const int target_size,
                     int* out_width, int* out_height);

#endif // IMAGE_UTILS_H
