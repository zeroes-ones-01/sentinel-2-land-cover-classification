
# =============================================================================
# Project: Sentinel-2 Land-Cover Classification in Gewata
# Script: 01_sentinel2_land_cover_classification.R
#
# Objective:
# Prepare Sentinel-2 imagery, classify cropland, forest and wetland using
# a Random Forest model, and examine the spatial pattern of forest patches.
#
# Study area: Gewata, Ethiopia
# Sentinel-2 acquisition date: 27 December 2020
# Spatial resolution: 20 m
#
# Software: R, terra, sf, ranger
#
# Attribution:
# This work was completed as part of the WUR GeoScripting Advanced Raster
# Analysis practical. The workflow is adapted from:
# https://github.com/GeoScripting-WUR/AdvancedRasterAnalysis
#
# The original practical is distributed under CC BY-SA 4.0.
# Consult the original source for attribution and licence conditions.
#
# Assessment:
# Model performance is assessed using out-of-bag (OOB) estimates.
# No independent validation is claimed in this analysis.
#
# =============================================================================


# 1. PROJECT SETUP ------------------------------------------------------------

find_project_root <- function(start = getwd()) {

  current <- normalizePath(
    start,
    winslash = "/",
    mustWork = TRUE
  )

  sentinel_relative <- file.path(
    "Data", "Raw data", "AdvancedRaster",
    "S2B2A_T36NZP_20201227T075239_20m_gewata_crop.tif"
  )

  repeat {

    if (file.exists(file.path(current, sentinel_relative))) {
      return(current)
    }

    parent <- dirname(current)

    if (identical(parent, current)) {
      stop(
        "Project root could not be located. ",
        "Set the working directory to a folder inside the project."
      )
    }

    current <- parent
  }
}

project_root <- find_project_root()

message("Project root: ", project_root)


# 2. LOAD PACKAGES ------------------------------------------------------------

required_packages <- c("terra", "sf", "ranger")

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0) {
  stop(
    "Install the following missing packages before proceeding: ",
    paste(missing_packages, collapse = ", ")
  )
}

library(terra)
library(sf)
library(ranger)

package_versions <- data.frame(
  Package = required_packages,
  Version = vapply(
    required_packages,
    function(pkg) as.character(packageVersion(pkg)),
    character(1)
  )
)

message("Package versions:")
print(package_versions)


# 3. DEFINE INPUT FILES -------------------------------------------------------

sentinel_file <- file.path(
  project_root,
  "Data", "Raw data", "AdvancedRaster",
  "S2B2A_T36NZP_20201227T075239_20m_gewata_crop.tif"
)

training_file <- file.path(
  project_root,
  "Data", "Raw data",
  "trainingPoly.csv"
)

if (!file.exists(sentinel_file)) {
  stop("Sentinel-2 raster not found: ", sentinel_file)
}

if (!file.exists(training_file)) {
  stop("Training polygon file not found: ", training_file)
}


# 4. LOAD AND PREPARE SENTINEL-2 IMAGERY --------------------------------------

Gewata <- terra::rast(sentinel_file)

if (terra::nlyr(Gewata) != 10) {
  stop("Expected ten raster layers. Check the source raster.")
}

# Assign the confirmed Sentinel-2 band names.

names(Gewata) <- c(
  "B02", "B03", "B04", "B05", "B06",
  "B07", "B11", "B12", "B8A", "SCL"
)

# Remove the Scene Classification Layer.

Gewata <- terra::subset(
  Gewata,
  "SCL",
  negate = TRUE
)

stopifnot(terra::nlyr(Gewata) == 9)

message("Sentinel-2 bands retained:")
print(names(Gewata))

message("Sentinel-2 raster information:")
print(Gewata)

message("Mean band values:")
print(terra::global(Gewata, "mean", na.rm = TRUE))


# 5. CALCULATE NDVI ------------------------------------------------------------

# NDVI = (NIR - Red) / (NIR + Red)
# B8A = near-infrared
# B04 = red

ndvi <- terra::app(
  c(Gewata$B8A, Gewata$B04),
  fun = function(x) {
    (x[1] - x[2]) / (x[1] + x[2])
  }
)

names(ndvi) <- "NDVI"

plot(
  ndvi,
  main = "Normalised Difference Vegetation Index (NDVI)"
)


# 6. LOAD AND PREPARE TRAINING POLYGONS ---------------------------------------

trainingPoly <- sf::st_read(
  training_file,
  quiet = TRUE
)

if (!inherits(trainingPoly, "sf")) {
  stop("Training data did not load as an sf object.")
}

if (!"Class" %in% names(trainingPoly)) {
  stop("The training polygon data must contain a Class column.")
}

if (is.na(sf::st_crs(trainingPoly))) {

  # The polygon coordinate ranges and spatial extent were checked
  # against the Sentinel-2 raster. They are consistent with EPSG:32636.
  # Assigning the CRS defines the coordinates; it does not transform them.

  sf::st_crs(trainingPoly) <- 32636
}

# Confirm the training polygon CRS against the raster CRS.

raster_crs <- sf::st_crs(terra::crs(Gewata))

if (is.na(raster_crs)) {
  stop("Could not interpret the Sentinel-2 raster CRS.")
}

if (sf::st_crs(trainingPoly) != raster_crs) {

  trainingPoly <- sf::st_transform(
    trainingPoly,
    raster_crs
  )
}

message("Training polygon CRS:")
print(sf::st_crs(trainingPoly))

trainingPoly$Class <- as.factor(trainingPoly$Class)

message("Training polygon counts:")
print(table(trainingPoly$Class))

# Display the training polygons over the NDVI image.

plot(
  ndvi,
  main = "Training Polygons over NDVI"
)

class_colours <- c(
  cropland = "orange",
  forest = "darkgreen",
  wetland = "lightblue"
)

for (class_name in names(class_colours)) {

  selected_polygons <- trainingPoly[
    as.character(trainingPoly$Class) == class_name,
  ]

  if (nrow(selected_polygons) > 0) {
    plot(
      sf::st_geometry(selected_polygons),
      add = TRUE,
      border = class_colours[[class_name]],
      lwd = 1
    )
  }
}


# 7. PREPARE PREDICTOR VARIABLES ----------------------------------------------

# Scale Sentinel-2 reflectance values by 10,000.

gewata <- terra::app(
  Gewata,
  fun = function(x) x / 10000
)

# Combine nine spectral bands with NDVI.

covs <- c(
  gewata,
  ndvi
)

names(covs) <- c(
  names(Gewata),
  "NDVI"
)

message("Predictor variables:")
print(names(covs))

stopifnot(terra::nlyr(covs) == 10)


# 8. EXTRACT TRAINING DATA -----------------------------------------------------

trainingData <- terra::extract(
  covs,
  trainingPoly
)

# Attach the corresponding training class.

trainingData$Class <- trainingPoly$Class[
  trainingData$ID
]

# Remove the extraction ID column.

trainingData$ID <- NULL

# Remove incomplete observations.

trainingData <- trainingData[
  complete.cases(trainingData),
]

trainingData$Class <- droplevels(
  as.factor(trainingData$Class)
)

if (nrow(trainingData) == 0) {
  stop("No complete training observations were extracted.")
}

message("Extracted training observations:")
print(nrow(trainingData))

message("Observations by class:")
print(table(trainingData$Class))

message("Training data structure:")
str(trainingData)


# 9. EXPLORATORY ANALYSIS ------------------------------------------------------

# Examine NDVI distributions by class.

boxplot(
  NDVI ~ Class,
  data = trainingData,
  main = "NDVI Distribution by Land-Cover Class",
  xlab = "Land-cover class",
  ylab = "NDVI"
)

# Examine selected predictor relationships.

plot(
  trainingData$B8A,
  trainingData$B11,
  col = as.integer(trainingData$Class),
  pch = 16,
  cex = 0.3,
  xlab = "B8A",
  ylab = "B11",
  main = "B8A versus B11 by Class"
)

legend(
  "topright",
  legend = levels(trainingData$Class),
  col = seq_along(levels(trainingData$Class)),
  pch = 16,
  cex = 0.8
)


# 10. RANDOM FOREST CLASSIFICATION --------------------------------------------

set.seed(0xfedbeef)

modelRF <- ranger::ranger(
  Class ~ .,
  data = trainingData,
  num.trees = 100,
  importance = "permutation",
  seed = 0xfedbeef
)

# Report out-of-bag performance.

oob_error <- modelRF$prediction.error
oob_accuracy <- 1 - oob_error

message("Out-of-bag error:")
print(oob_error)

message("Out-of-bag accuracy:")
print(oob_accuracy)

message("Out-of-bag confusion matrix:")
print(modelRF$confusion.matrix)

# Calculate class-specific recall.

confusion_matrix <- modelRF$confusion.matrix

class_recall <- diag(confusion_matrix) /
  rowSums(confusion_matrix)

recall_table <- data.frame(
  Class = rownames(confusion_matrix),
  Recall = class_recall
)

message("Class-specific recall:")
print(recall_table)


# 11. VARIABLE IMPORTANCE -----------------------------------------------------

variable_importance <- sort(
  modelRF$variable.importance,
  decreasing = TRUE
)

message("Random Forest variable importance:")
print(variable_importance)

barplot(
  variable_importance,
  las = 2,
  main = "Random Forest Variable Importance",
  ylab = "Permutation importance"
)


# 12. PREDICT LAND-COVER CLASSES ----------------------------------------------

predLC <- terra::predict(
  covs,
  modelRF,
  fun = function(model, data, ...) {
    predict(model, data)$predictions
  }
)

names(predLC) <- "Land_cover"

message("Predicted land-cover raster:")
print(predLC)

plot(
  predLC,
  main = "Sentinel-2 Land-Cover Classification"
)


# 13. CALCULATE LAND-COVER AREA -----------------------------------------------

# The predicted raster stores numeric category codes:
# 1 = cropland, 2 = forest, 3 = wetland.
#
# freq(predLC) displays category labels. Therefore, use the underlying
# numeric raster values for pixel counting.

class_levels <- modelRF$forest$levels

raster_values <- terra::values(
  predLC,
  mat = FALSE
)

predicted_codes <- sort(
  unique(raster_values[!is.na(raster_values)])
)

if (!identical(
  as.integer(predicted_codes),
  seq_along(class_levels)
)) {
  stop(
    "Predicted raster codes do not match the model class levels."
  )
}

class_counts <- tabulate(
  as.integer(raster_values[!is.na(raster_values)]),
  nbins = length(class_levels)
)

# Pixel area in square kilometres.

pixel_area_km2 <- prod(
  terra::res(predLC)
) / 1000000

class_area <- data.frame(
  Class = class_levels,
  Pixel_Count = class_counts,
  Area_km2 = class_counts * pixel_area_km2
)

message("Land-cover class areas:")
print(class_area)

message("Total classified area (km²):")
print(sum(class_area$Area_km2))

# Confirm that all non-NA raster pixels have been counted.

non_na_pixels <- sum(
  !is.na(raster_values)
)

if (sum(class_counts) != non_na_pixels) {
  stop("Class pixel counts do not match the classified raster.")
}


# 14. PREPARE FOREST MASK ------------------------------------------------------

# Identify the numeric class code for forest from the model levels.

forest_code <- match(
  "forest",
  class_levels
)

if (is.na(forest_code)) {
  stop("The forest class was not found in the model.")
}

# Create a raster containing forest pixels only.

formask <- terra::setValues(
  predLC,
  NA
)

formask[
  predLC == forest_code
] <- 1

plot(
  formask,
  col = "yellow",
  main = "Forest Mask"
)


# 15. FOREST PATCH ANALYSIS: QUEEN'S CASE -------------------------------------

# Eight-neighbour connectivity:
# diagonal neighbours are considered connected.

patchesForest <- terra::patches(
  formask,
  directions = 8
)

patchFreq <- terra::freq(patchesForest)

queen_single_pixel <- sum(
  patchFreq$count == 1,
  na.rm = TRUE
)

message("Queen's case patch count:")
print(nrow(patchFreq))

message("Queen's case single-pixel patches:")
print(queen_single_pixel)


# 16. FOREST PATCH ANALYSIS: ROOK'S CASE --------------------------------------

# Four-neighbour connectivity:
# only edge-sharing neighbours are considered connected.

patchesRook <- terra::patches(
  formask,
  directions = 4
)

patchFreqRook <- terra::freq(patchesRook)

rook_single_pixel <- sum(
  patchFreqRook$count == 1,
  na.rm = TRUE
)

message("Rook's case patch count:")
print(nrow(patchFreqRook))

message("Rook's case single-pixel patches:")
print(rook_single_pixel)


# 17. APPLY A 0.5 HECTARE MINIMUM MAPPING UNIT -------------------------------

# 0.5 hectares = 5,000 m².
# Calculate the minimum whole number of pixels required.

pixel_area_m2 <- abs(
  prod(terra::res(formask))
)

minimum_area_m2 <- 5000

minimum_pixels <- ceiling(
  minimum_area_m2 / pixel_area_m2
)

message("Pixel area (m²):")
print(pixel_area_m2)

message("Minimum pixels for 0.5 hectares:")
print(minimum_pixels)

# Remove Queen's case forest patches below the threshold.

excludeID <- patchFreq$value[
  patchFreq$count < minimum_pixels
]

formaskSieve05 <- formask

formaskSieve05[
  patchesForest %in% excludeID
] <- NA

plot(
  formaskSieve05,
  col = "darkgreen",
  main = "Forest Patches at Least 0.5 ha"
)


# 18. SAVE REPRODUCIBLE OUTPUTS -----------------------------------------------

# Create a unique timestamped directory for this run.
# Existing output folders and files are not overwritten.

run_timestamp <- format(
  Sys.time(),
  "%Y%m%d_%H%M%S"
)

output_dir <- file.path(
  project_root,
  "Outputs",
  paste0("sentinel2_classification_", run_timestamp)
)

if (dir.exists(output_dir)) {
  stop(
    "Output directory already exists: ",
    output_dir,
    "\nRun the script again at a different time."
  )
}

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!dir.exists(output_dir)) {
  stop("Could not create the output directory.")
}

# Save extracted training observations.

write.csv(
  trainingData,
  file.path(output_dir, "training_data.csv"),
  row.names = FALSE
)

# Save the fitted Random Forest model.

saveRDS(
  modelRF,
  file.path(output_dir, "random_forest_model.rds")
)

# Save the predicted land-cover raster.

terra::writeRaster(
  predLC,
  file.path(output_dir, "sentinel2_land_cover.tif"),
  overwrite = FALSE
)

# Save the original forest mask.

terra::writeRaster(
  formask,
  file.path(output_dir, "forest_mask.tif"),
  overwrite = FALSE
)

# Save the forest mask after applying the 0.5 ha threshold.

terra::writeRaster(
  formaskSieve05,
  file.path(output_dir, "forest_mask_05ha.tif"),
  overwrite = FALSE
)

# Save land-cover area estimates.

write.csv(
  class_area,
  file.path(output_dir, "land_cover_area.csv"),
  row.names = FALSE
)

# Save model performance metrics.

model_metrics <- data.frame(
  Metric = c("OOB error", "OOB accuracy"),
  Value = c(oob_error, oob_accuracy)
)

write.csv(
  model_metrics,
  file.path(output_dir, "model_performance.csv"),
  row.names = FALSE
)

# Save class-specific recall.

write.csv(
  recall_table,
  file.path(output_dir, "class_recall.csv"),
  row.names = FALSE
)

# Save variable importance.

importance_table <- data.frame(
  Predictor = names(variable_importance),
  Importance = as.numeric(variable_importance)
)

write.csv(
  importance_table,
  file.path(output_dir, "variable_importance.csv"),
  row.names = FALSE
)

# Save forest patch summaries.

patch_summary <- data.frame(
  Connectivity = c("Queen's case", "Rook's case"),
  Patch_Count = c(
    nrow(patchFreq),
    nrow(patchFreqRook)
  ),
  Single_Pixel_Patches = c(
    queen_single_pixel,
    rook_single_pixel
  )
)

write.csv(
  patch_summary,
  file.path(output_dir, "forest_patch_summary.csv"),
  row.names = FALSE
)

# Save minimum mapping unit information.

sieve_summary <- data.frame(
  Pixel_Area_m2 = pixel_area_m2,
  Minimum_Area_m2 = minimum_area_m2,
  Minimum_Pixels = minimum_pixels
)

write.csv(
  sieve_summary,
  file.path(output_dir, "forest_sieving_parameters.csv"),
  row.names = FALSE
)

message("Analysis completed successfully.")
message("Generated outputs saved to:")
message(output_dir)


# =============================================================================
# END OF SCRIPT
# =============================================================================
