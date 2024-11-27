// onnx_bridge.h
#ifndef ONNX_BRIDGE_H
#define ONNX_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OnnxContext OnnxContext;

typedef struct {
    float x;
    float y;
} Point;

typedef struct {
    unsigned char* data;
    int width;
    int height;
    int channels;
} ImageData;

typedef struct {
    float* mask;
    int width;
    int height;
    float score;  // IoU score
} SegmentationResult;

// Create and destroy context
OnnxContext* create_onnx_context(const char* encoder_path, const char* decoder_path);
void destroy_onnx_context(OnnxContext* ctx);

// Process image and generate embeddings
int process_image(OnnxContext* ctx, const ImageData* image);

// Run segmentation with cached embeddings
int run_segmentation(OnnxContext* ctx, 
                    const Point* points,
                    int num_points,
                    const int orig_width,
                    const int orig_height,
                    SegmentationResult* result);

// Get last error message
const char* get_last_error(OnnxContext* ctx);

// Cleanup
void free_segmentation_result(SegmentationResult* result);

#ifdef __cplusplus
}
#endif

#endif // ONNX_BRIDGE_H
