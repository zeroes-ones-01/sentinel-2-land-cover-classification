# Data Sources and Preparation

This document describes the source datasets, their provenance and the directory structure required to reproduce the Sentinel-2 land-cover classification analysis.

## 1. Sentinel-2 imagery

The satellite imagery was obtained from the Wageningen University (WUR) Geoscripting Advanced Raster Analysis practical materials.

**Source repository:**\
https://github.com/GeoScripting-WUR/AdvancedRasterAnalysis

**Source data archive:**\
https://github.com/GeoScripting-WUR/AdvancedRasterAnalysis/releases/download/advrast-data/AdvancedRaster.zip

**Image file used:**

`S2B2A_T36NZP_20201227T075239_20m_gewata_crop.tif`

**Acquisition date:** 27 December 2020\
**Spatial resolution:** 20 metres\
**Study area:** Gewata, Ethiopia\
**Coordinate reference system:** EPSG:32636 (WGS 84 / UTM zone 36N)

The image contains nine spectral bands used in the analysis. The Scene Classification Layer (SCL) is excluded from the predictor stack.

The accompanying band metadata file is:

`S2B2A_T36NZP_20201227T075239_20m_gewata_bands.txt`

## 2. Reference training polygons

The reference training polygons were supplied with the original WUR practical materials.

**Source file:** `trainingPoly.csv`

**Download:**\
https://github.com/GeoScripting-WUR/AdvancedRasterAnalysis/releases/download/advrast-data/trainingPoly.csv

The dataset contains 16 reference polygons:

| Land-cover class | Number of polygons |
|---|---:|
| Cropland | 6 |
| Forest | 5 |
| Wetland | 5 |
| **Total** | **16** |

The original CSV does not specify a coordinate reference system. In this analysis, EPSG:32636 was assigned following coordinate-range and spatial consistency checks. This assignment is an analytical assumption and should not be interpreted as CRS metadata supplied by the original data provider.

The polygons are source reference data, not newly collected field observations.

## 3. Required directory structure

Download and extract the source files into the following locations within the project:

```text
Data/
└── Raw data/
    ├── AdvancedRaster/
    │   ├── S2B2A_T36NZP_20201227T075239_20m_gewata_crop.tif
    │   └── S2B2A_T36NZP_20201227T075239_20m_gewata_bands.txt
    │
    └── trainingPoly.csv
```

The main analysis script expects these exact relative locations:

- `Data/Raw data/AdvancedRaster/S2B2A_T36NZP_20201227T075239_20m_gewata_crop.tif`
- `Data/Raw data/trainingPoly.csv`

The band metadata file is retained for reference and documentation.

## 4. Data preparation

For this project:

1. The Sentinel-2 raster was loaded into R using the `terra` package.
2. The spectral layers were assigned their corresponding band names.
3. The SCL layer was excluded from the predictor stack.
4. NDVI was calculated using B8A and B04.
5. The training polygons were loaded using the `sf` package.
6. EPSG:32636 was assigned to the training polygons following spatial consistency checks, because the source CSV did not provide CRS information.
7. Training pixels were extracted from the predictor stack for Random Forest model fitting.

The original source datasets were retained separately from the generated classification outputs.

## 5. Data attribution and reuse

The Sentinel-2 imagery originates from Copernicus Sentinel data. The recommended acknowledgement is:

**Contains modified Copernicus Sentinel data 2020.**

The training polygons and practical materials originate from the WUR Advanced Raster Analysis course.

Consult the original source repository, course documentation and applicable data terms before redistributing the source materials. The licence associated with the practical course materials should not automatically be assumed to cover every individual dataset in the distribution.

This repository therefore documents the source locations and reproduction procedure rather than redistributing the original satellite image or training polygon file.

## 6. Reproducibility note

The analysis depends on the source files being placed in the specified directory structure. If the files are stored elsewhere, the paths used by the main R script will need to be adjusted.

The published figures and summary CSV files are derived analytical outputs. They should not be confused with the original source datasets.
