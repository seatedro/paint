// onnx_bridge.c
#include "onnx_bridge.h"
#include "image_utils.h"
#include <math.h>
#include <onnxruntime_c_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ERROR_MSG 1024
#define TARGET_SIZE 1024
#define MASK_INPUT_SIZE 256

struct OnnxContext {
  const OrtApi *api;
  OrtEnv *env;
  OrtSession *encoder_session;
  OrtSession *decoder_session;
  OrtMemoryInfo *memory_info;
  char last_error[MAX_ERROR_MSG];
  float *image_embeddings;
  int64_t embedding_dims[4];
  int model_width;
  int model_height;
};

static void set_error(OnnxContext *ctx, const char *error) {
  if (ctx && error) {
    strncpy(ctx->last_error, error, MAX_ERROR_MSG - 1);
    ctx->last_error[MAX_ERROR_MSG - 1] = '\0';
    printf("ONNX Error: %s\n", error);
  }
}

static OrtValue *create_tensor(OnnxContext *ctx, const float *data,
                               const int64_t *shape, const size_t rank,
                               const char *debug_name) {
  OrtValue *tensor = NULL;
  size_t total_elements = 1;
  for (size_t i = 0; i < rank; i++) {
    total_elements *= shape[i];
  }

  printf("Creating tensor '%s' with shape [", debug_name);
  for (size_t i = 0; i < rank; i++) {
    printf("%lld%s", shape[i], i < rank - 1 ? ", " : "");
  }
  printf("]\n");

  OrtStatus *status = ctx->api->CreateTensorWithDataAsOrtValue(
      ctx->memory_info, (void *)data, total_elements * sizeof(float), shape,
      rank, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &tensor);

  if (status != NULL) {
    const char *error_message = ctx->api->GetErrorMessage(status);
    printf("Error creating tensor '%s': %s\n", debug_name, error_message);
    ctx->api->ReleaseStatus(status);
    return NULL;
  }

  return tensor;
}

OnnxContext *create_onnx_context(const char *encoder_path,
                                 const char *decoder_path) {
  printf("Creating ONNX context...\n");

  OnnxContext *ctx = (OnnxContext *)calloc(1, sizeof(OnnxContext));
  if (!ctx) {
    printf("Error: Failed to allocate context\n");
    return NULL;
  }

  ctx->api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  if (!ctx->api) {
    printf("Error: Failed to get ONNX Runtime API\n");
    free(ctx);
    return NULL;
  }

  OrtStatus *status =
      ctx->api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "mobilesam", &ctx->env);
  if (status != NULL) {
    const char *msg = ctx->api->GetErrorMessage(status);
    printf("Error creating environment: %s\n", msg);
    ctx->api->ReleaseStatus(status);
    free(ctx);
    return NULL;
  }

  // Create session options
  OrtSessionOptions *session_options = NULL;
  status = ctx->api->CreateSessionOptions(&session_options);
  if (status != NULL) {
    const char *msg = ctx->api->GetErrorMessage(status);
    printf("Error creating session options: %s\n", msg);
    ctx->api->ReleaseStatus(status);
    ctx->api->ReleaseEnv(ctx->env);
    free(ctx);
    return NULL;
  }

  printf("Creating encoder session from: %s\n", encoder_path);
  status = ctx->api->CreateSession(ctx->env, encoder_path, session_options,
                                   &ctx->encoder_session);
  if (status != NULL) {
    const char *msg = ctx->api->GetErrorMessage(status);
    printf("Error creating encoder session: %s\n", msg);
    ctx->api->ReleaseStatus(status);
    ctx->api->ReleaseSessionOptions(session_options);
    ctx->api->ReleaseEnv(ctx->env);
    free(ctx);
    return NULL;
  }

  printf("Creating decoder session from: %s\n", decoder_path);
  status = ctx->api->CreateSession(ctx->env, decoder_path, session_options,
                                   &ctx->decoder_session);
  if (status != NULL) {
    const char *msg = ctx->api->GetErrorMessage(status);
    printf("Error creating decoder session: %s\n", msg);
    ctx->api->ReleaseStatus(status);
    ctx->api->ReleaseSessionOptions(session_options);
    ctx->api->ReleaseSession(ctx->encoder_session);
    ctx->api->ReleaseEnv(ctx->env);
    free(ctx);
    return NULL;
  }

  status = ctx->api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault,
                                         &ctx->memory_info);
  if (status != NULL) {
    const char *msg = ctx->api->GetErrorMessage(status);
    printf("Error creating memory info: %s\n", msg);
    ctx->api->ReleaseStatus(status);
    ctx->api->ReleaseSessionOptions(session_options);
    ctx->api->ReleaseSession(ctx->encoder_session);
    ctx->api->ReleaseSession(ctx->decoder_session);
    ctx->api->ReleaseEnv(ctx->env);
    free(ctx);
    return NULL;
  }

  ctx->api->ReleaseSessionOptions(session_options);
  printf("ONNX context created successfully\n");
  return ctx;
}

int process_image(OnnxContext *ctx, const ImageData *image) {
  if (!ctx || !image) {
    if (ctx)
      set_error(ctx, "Invalid parameters");
    return -1;
  }

  if (ctx->image_embeddings) {
    free(ctx->image_embeddings);
    ctx->image_embeddings = NULL;
  }

  int64_t input_shape[4];
  int newh, neww;
  float scale;
  float *preprocessed = preprocess_image(image, TARGET_SIZE, input_shape);
  if (!preprocessed) {
    set_error(ctx, "Image preprocessing failed");
    return -1;
  }

  ctx->model_width = (int)input_shape[3];
  ctx->model_height = (int)input_shape[2];

  OrtValue *input_tensor =
      create_tensor(ctx, preprocessed, input_shape, 4, "input_image");
  if (!input_tensor) {
    free(preprocessed);
    set_error(ctx, "Failed to create input tensor");
    return -1;
  }

  const char *input_names[] = {"images"};
  const char *output_names[] = {"image_embeddings"};
  OrtValue *output_tensor = NULL;

  printf("Running encoder...\n");
  OrtStatus *status = ctx->api->Run(ctx->encoder_session, NULL, input_names,
                                    (const OrtValue *const *)&input_tensor, 1,
                                    output_names, 1, &output_tensor);

  if (status != NULL) {
    const char *error_message = ctx->api->GetErrorMessage(status);
    printf("Encoder inference failed: %s\n", error_message);
    ctx->api->ReleaseStatus(status);
    ctx->api->ReleaseValue(input_tensor);
    free(preprocessed);
    set_error(ctx, "Encoder inference failed");
    return -1;
  }

  OrtTensorTypeAndShapeInfo *info;
  status = ctx->api->GetTensorTypeAndShape(output_tensor, &info);
  if (status == NULL) {
    size_t num_dims;
    status = ctx->api->GetDimensionsCount(info, &num_dims);
    status = ctx->api->GetDimensions(info, ctx->embedding_dims, num_dims);

    printf("Embedding dimensions: [%lld, %lld, %lld, %lld]\n",
           ctx->embedding_dims[0], ctx->embedding_dims[1],
           ctx->embedding_dims[2], ctx->embedding_dims[3]);

    ctx->api->ReleaseTensorTypeAndShapeInfo(info);
  }

  void *embedding_data;
  status = ctx->api->GetTensorMutableData(output_tensor, &embedding_data);
  if (status != NULL) {
    ctx->api->ReleaseValue(input_tensor);
    ctx->api->ReleaseValue(output_tensor);
    free(preprocessed);
    set_error(ctx, "Failed to get tensor data");
    return -1;
  }

  size_t embedding_size = ctx->embedding_dims[0] * ctx->embedding_dims[1] *
                          ctx->embedding_dims[2] * ctx->embedding_dims[3];
  ctx->image_embeddings = (float *)malloc(embedding_size * sizeof(float));
  if (!ctx->image_embeddings) {
    ctx->api->ReleaseValue(input_tensor);
    ctx->api->ReleaseValue(output_tensor);
    free(preprocessed);
    set_error(ctx, "Failed to allocate memory for embeddings");
    return -1;
  }

  memcpy(ctx->image_embeddings, embedding_data, embedding_size * sizeof(float));

  ctx->api->ReleaseValue(input_tensor);
  ctx->api->ReleaseValue(output_tensor);
  free(preprocessed);

  printf("Image processing complete. Embedding size: %zu\n", embedding_size);
  return 0;
}

int run_segmentation(OnnxContext *ctx, const Point *points, int num_points,
                     const int orig_width, const int orig_height,
                     SegmentationResult *result) {
  if (!ctx || !points || !result || !ctx->image_embeddings) {
    if (ctx)
      set_error(ctx, "Invalid parameters or no image embeddings");
    return -1;
  }

  printf("Running segmentation with %d points...\n", num_points);

  // Create point coordinates with padding point
  const int total_points = num_points + 1;
  float *point_coords = (float *)malloc(total_points * 2 * sizeof(float));
  if (!point_coords) {
    set_error(ctx, "Memory allocation failed for coordinates");
    return -1;
  }

  // Copy points to float array
  for (int i = 0; i < num_points; i++) {
    point_coords[i * 2] = points[i].x;
    point_coords[i * 2 + 1] = points[i].y;
  }
  // Add padding point
  point_coords[num_points * 2] = 0.0f;
  point_coords[num_points * 2 + 1] = 0.0f;

  int resized_width, resized_height;
  transform_coords(point_coords, 2, orig_width, orig_height, TARGET_SIZE,
                   &resized_width, &resized_height);

  // Create point labels (1 for all points, -1 for padding)
  float *point_labels = (float *)malloc(total_points * sizeof(float));
  if (!point_labels) {
    free(point_coords);
    set_error(ctx, "Memory allocation failed for labels");
    return -1;
  }
  for (int i = 0; i < num_points; i++) {
    point_labels[i] = 1.0f;
  }
  point_labels[num_points] = -1.0f; // padding point label

  // Create empty mask input
  float *mask_input =
      (float *)calloc(1 * 1 * MASK_INPUT_SIZE * MASK_INPUT_SIZE, sizeof(float));
  if (!mask_input) {
    free(point_coords);
    free(point_labels);
    set_error(ctx, "Memory allocation failed for mask");
    return -1;
  }

  // Prepare inputs
  float has_mask_input = 0.0f;
  float orig_size[2] = {(float)orig_height, (float)orig_width};

  // Define shapes
  int64_t coords_shape[] = {1, total_points, 2};
  int64_t labels_shape[] = {1, total_points};
  int64_t mask_shape[] = {1, 1, MASK_INPUT_SIZE, MASK_INPUT_SIZE};
  int64_t has_mask_shape[] = {1};
  int64_t orig_size_shape[] = {2};

  // Create input tensors
  OrtValue *input_tensors[6] = {NULL};
  input_tensors[0] = create_tensor(ctx, ctx->image_embeddings,
                                   ctx->embedding_dims, 4, "image_embeddings");
  input_tensors[1] =
      create_tensor(ctx, point_coords, coords_shape, 3, "point_coords");
  input_tensors[2] =
      create_tensor(ctx, point_labels, labels_shape, 2, "point_labels");
  input_tensors[3] =
      create_tensor(ctx, mask_input, mask_shape, 4, "mask_input");
  input_tensors[4] =
      create_tensor(ctx, &has_mask_input, has_mask_shape, 1, "has_mask_input");
  input_tensors[5] =
      create_tensor(ctx, orig_size, orig_size_shape, 1, "orig_im_size");

  // Check tensor creation
  for (int i = 0; i < 6; i++) {
    if (!input_tensors[i]) {
      for (int j = 0; j < i; j++) {
        if (input_tensors[j])
          ctx->api->ReleaseValue(input_tensors[j]);
      }
      free(point_coords);
      free(point_labels);
      free(mask_input);
      set_error(ctx, "Failed to create input tensors");
      return -1;
    }
  }

  // Run inference
  const char *input_names[] = {"image_embeddings", "point_coords",
                               "point_labels",     "mask_input",
                               "has_mask_input",   "orig_im_size"};
  const char *output_names[] = {"masks", "iou_predictions", "low_res_masks"};
  OrtValue *output_tensors[3] = {NULL};

  printf("Running decoder...\n");
  OrtStatus *status = ctx->api->Run(ctx->decoder_session, NULL, input_names,
                                    (const OrtValue *const *)input_tensors, 6,
                                    output_names, 3, output_tensors);

  if (status != NULL) {
    const char *error_message = ctx->api->GetErrorMessage(status);
    printf("Decoder inference failed: %s\n", error_message);
    ctx->api->ReleaseStatus(status);
    for (int i = 0; i < 6; i++) {
      if (input_tensors[i])
        ctx->api->ReleaseValue(input_tensors[i]);
    }
    free(point_coords);
    free(point_labels);
    free(mask_input);
    set_error(ctx, "Decoder inference failed");
    return -1;
  }

  // Get mask and IoU prediction data
  float *mask_data;
  float *iou_data;
  status =
      ctx->api->GetTensorMutableData(output_tensors[0], (void **)&mask_data);
  if (status == NULL) {
    status =
        ctx->api->GetTensorMutableData(output_tensors[1], (void **)&iou_data);
  }

  if (status != NULL) {
    for (int i = 0; i < 6; i++) {
      if (input_tensors[i])
        ctx->api->ReleaseValue(input_tensors[i]);
    }
    for (int i = 0; i < 3; i++) {
      if (output_tensors[i])
        ctx->api->ReleaseValue(output_tensors[i]);
    }
    free(point_coords);
    free(point_labels);
    free(mask_input);
    set_error(ctx, "Failed to get output tensor data");
    return -1;
  }

  // Get output mask dimensions
  OrtTensorTypeAndShapeInfo *mask_info;
  int64_t mask_dims[4] = {0};
  status = ctx->api->GetTensorTypeAndShape(output_tensors[0], &mask_info);
  if (status == NULL) {
    size_t num_dims;
    status = ctx->api->GetDimensionsCount(mask_info, &num_dims);
    status = ctx->api->GetDimensions(mask_info, mask_dims, num_dims);
    if (status != NULL) {
      printf("Warning: Failed to get mask dimensions\n");
    }
    printf("Output mask dimensions: [%lld, %lld, %lld, %lld]\n", mask_dims[0],
           mask_dims[1], mask_dims[2], mask_dims[3]);
    ctx->api->ReleaseTensorTypeAndShapeInfo(mask_info);
  }

  // Initialize result
  result->width = orig_width;
  result->height = orig_height;
  result->score = iou_data[0];
  result->mask = (float *)malloc(orig_width * orig_height * sizeof(float));
  if (!result->mask) {
    for (int i = 0; i < 6; i++) {
      if (input_tensors[i])
        ctx->api->ReleaseValue(input_tensors[i]);
    }
    for (int i = 0; i < 3; i++) {
      if (output_tensors[i])
        ctx->api->ReleaseValue(output_tensors[i]);
    }
    free(point_coords);
    free(point_labels);
    free(mask_input);
    set_error(ctx, "Failed to allocate result mask");
    return -1;
  }

  // Convert mask logits to binary mask and resize to original dimensions
  const float threshold = 0.0f; // MobileSAM threshold

  // The mask comes in orig_width x orig_height size from the model
  // due to the orig_im_size input parameter
  for (size_t i = 0; i < orig_width * orig_height; i++) {
    result->mask[i] = mask_data[i] > threshold ? 1.0f : 0.0f;
  }

  printf("Segmentation complete. IoU score: %.3f\n", result->score);

  // Cleanup
  for (int i = 0; i < 6; i++) {
    if (input_tensors[i])
      ctx->api->ReleaseValue(input_tensors[i]);
  }
  for (int i = 0; i < 3; i++) {
    if (output_tensors[i])
      ctx->api->ReleaseValue(output_tensors[i]);
  }
  free(point_coords);
  free(point_labels);
  free(mask_input);

  return 0;
}

void free_segmentation_result(SegmentationResult *result) {
  if (result && result->mask) {
    free(result->mask);
    result->mask = NULL;
    result->width = 0;
    result->height = 0;
    result->score = 0.0f;
  }
}

const char *get_last_error(OnnxContext *ctx) {
  return ctx ? ctx->last_error : "Invalid context";
}

void destroy_onnx_context(OnnxContext *ctx) {
  if (!ctx)
    return;

  if (ctx->encoder_session)
    ctx->api->ReleaseSession(ctx->encoder_session);
  if (ctx->decoder_session)
    ctx->api->ReleaseSession(ctx->decoder_session);
  if (ctx->env)
    ctx->api->ReleaseEnv(ctx->env);
  if (ctx->memory_info)
    ctx->api->ReleaseMemoryInfo(ctx->memory_info);
  if (ctx->image_embeddings)
    free(ctx->image_embeddings);

  free(ctx);
  printf("ONNX context destroyed\n");
}
