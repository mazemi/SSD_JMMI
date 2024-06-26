# ============================================== START ==========================================================

# This script analyses data from the DATA worksheet and saves in the ANALYSIS worksheet.
# 
# delete all data in environment:
{
  rm(list = ls(all = TRUE))

  # ///////////////////////////////////////////////////////////////
  # ///                                                         ///
  # ///    THE FOLLOWING LINES NEED ADJUSTMENT EVERY MONTH:     ///
  # ///                                                         ///
  # ///    Define current month:                                ///
  month_curr  <- 04       # adjust value if needed!    ///
  year_curr   <- 2024     # "                          ///
  # ///                                                         ///
  # ///    Define previous month:                               ///
  month_prev  <- 03       # adjust value if needed!     ///
  year_prev   <- 2024    # "                          ///
  # ///                                                         ///
  # ///    Define month 3 months behind:                       ///
  month_lag_3  <- 12       # adjust value if needed!     ///
  year_lag_3   <- 2023 
  # ///    Define month for longterm changes:                   ///
  month_long  <- 04        # adjust value if needed!    ///
  year_long   <- 2023     #                                      ///
  # ///                                                         ///
  # ///////////////////////////////////////////////////////////////

  # load packages:
  library(dplyr) # to restructure and aggregate the data
  library(openxlsx) # to read and export Excel files
  library(tidyr) # to tidy and format data
  library(rlang)
  library(purrr)
  library(tibble)
  library(sf)
  library(ggplot2)

  # load all the data:
  jmmi <- read.xlsx("./JMMI_data.xlsx", sheet = "CLEAN", colNames = TRUE)
  write.csv(jmmi, "./1_import/JMMI_data.csv", na = "", row.names = FALSE)
  jmmi <- read.csv("./1_import/JMMI_data.csv", stringsAsFactors = FALSE)
  feedback <- read.xlsx("./JMMI_data.xlsx", sheet = "feedback", colNames = TRUE)
  jmmi.raw <- read.xlsx("./1_import/raw.xlsx", sheet = 1, colNames = TRUE)
  longterm <- read.csv("./6_longterm/JMMI_longterm_bylocation.csv", header = TRUE)
  median.indices <- read.xlsx("./JMMI_analysis.xlsx", sheet = "median", colNames = TRUE)

  # the path of necessary files for producing border map image: 
  shapefile <- st_read("./data/shapefile/ssd_states.shp")
  borders.geo.info <- read.xlsx("./data/border_geo_info.xlsx")
  
  # the path of two final excel files: 
  result1.file.path <- "result1.xlsx"
  result2.file.path <- "result2.xlsx"
  
  # =========================== DEFINE ALL FUNCTIONS TO BE USED THROUGHOUT THE ANALYSIS SHEET ==========================

  # This is useful as sometimes functions are used multiple times throughout the script - the number appears again where the function is used

  # --------- 1

  # create a function to flag if there is one quotation, if the unit is a JMMI mug and it's either over 2 or under 2 times the national median

  quote_check <- function(x) {
    ifelse(sum(x %in% "!") > 0, "!", "")
  }

  # --------- 2

  # Next, the aggregation function for availability is defined. The logic is that if an item is available from at least 1 trader, then it is considered "available"
  # in the location. If it is not normally available from any trader, but is limitedly available from at least 1 trader, then it is considered "limited" in the location.
  # If none of the traders have the item in stock (not even limited), then the items is considered "unavailable".

  availability <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "available") > 0) {
      return("av")
    } else if (sum(x %in% "limited" | x %in% "available") > 0) {
      return("lim")
    } else if (sum(x %in% "unavailable") > 0) {
      return("un")
    } else {
      return("un")
    }
  }

  # --------- 3

  # Price expectation aggregation function:

  expectation.price <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "increase") > 1 & sum(x %in% "decrease") > 1) {
      return("NC")
    } else if (sum(x %in% "decrease") > 1) {
      return("decrease")
    } else if (sum(x %in% "increase") > 1) {
      return("increase")
    } else if (sum(x %in% "no_change") > 1) {
      return("decrease")
    } else if (sum(x %in% "increase" | x %in% "decrease" | x %in% "no_change") > 0) {
      return("NC")
    } else {
      return("")
    }
  }

  # --------- 4

  # Define restock aggregation function. Overall location response is "yes" if at least one trader is currently able to restock - otherwise the answer is "no".

  restock <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "yes") > 0) {
      return("yes")
    } else if (sum(x %in% "no") > 0) {
      return("no")
    } else {
      return("")
    }
  }

  # --------- 5

  # Define the restocked aggregation function (whether traders restocked in the last 30 days or not). The overall answer is "yes" if at least one trader reported "yes",
  # else "no" is returned.

  restocked <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "yes") > 0) {
      return("yes")
    } else if (sum(x %in% "no") > 0) {
      return("no")
    } else {
      return("")
    }
  }


  # --------- 6

  # Define border crossing aggregation function. Border crossing is considered "open" if at least 2 traders reported
  # so. The same thresholds of 2 also applies to "irregular and "closed", in order to have a minimum of triangulation
  # and to prevent a single, misinformed trader or clicking error do drive the overall aggregation.

  border.trader <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "open_normally") > 1) {
      return("open")
    } else if (sum(x %in% "open_normally_quarantine") > 1) {
      return("open")
    } else if (sum(x %in% "open_irregularly" | x %in% "open_normally") > 1) {
      return("irregular")
    } else if (sum(x %in% "open_irregularly_quarantine" | x %in% "open_normally") > 1) {
      return("irregular")
    } else if (sum(x %in% "open_irregularly" | x %in% "open_normally_quarantine") > 1) {
      return("irregular")
    } else if (sum(x %in% "open_irregularly_quarantine" | x %in% "open_normally_quarantine") > 1) {
      return("irregular")
    } else if ("closed" %in% x) {
      return("closed")
    } else {
      return("")
    }
  }

  # --------- 7

  # Make a function that measure if a certain border is subject to COVID-19 quarantine measures. Threshhold of 2 applies.

  border.trader.quarantine <- function(x) {
    if (sum(x %in% "open_normally_quarantine" | x %in% "open_irregularly_quarantine") > 1) {
      return("yes")
    } else {
      return("")
    }
  }

  # --------- 8

  # Define the border aggregation function for the responses from the feedback forms. As opposed to the previous function, the threshold here is 1 since we only have 1
  # feedback form per location.

  border.feedback <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "open_normally") > 0) {
      return("open")
    } else if (sum(x %in% "open_irregularly") > 0) {
      return("irregular")
    } else if ("closed" %in% x) {
      return("closed")
    } else {
      return("")
    }
  }

  # --------- 9

  # Define the road condition aggregation function. Same idea as border aggregation function (threshold of 2).

  road.trader <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "open") > 1) {
      return("open")
    } else if (sum(x %in% "warning_season" | x %in% "open") > 1) {
      return("irregular")
    } else if (sum(x %in% "warning_insecurity" | x %in% "open") > 1) {
      return("irregular")
    } else if (sum(x %in% "warning_restrictions" | x %in% "open") > 1) {
      return("irregular")
    } else if (sum(x %in% "closed_season") > 1) {
      return("closed")
    } else if (sum(x %in% "closed_insecurity") > 1) {
      return("closed")
    } else if (sum(x %in% "closed_restrictions") > 1) {
      return("closed")
    } else {
      return("")
    }
  }

  # --------- 10

  # Define road aggregation function for feedback form data:

  road.feedback <- function(x) {
    ux <- unique(x[!is.na(x)])

    if (sum(x %in% "open") > 0) {
      return("open")
    } else if (sum(x %in% "warning_season") > 0) {
      return("irregular")
    } else if (sum(x %in% "warning_insecurity") > 0) {
      return("irregular")
    } else if (sum(x %in% "warning_restrictions") > 0) {
      return("irregular")
    } else if (sum(x %in% "closed_season") > 0) {
      return("closed")
    } else if (sum(x %in% "closed_insecurity") > 0) {
      return("closed")
    } else if (sum(x %in% "closed_restrictions") > 0) {
      return("closed")
    } else {
      return("")
    }
  }

  # --------- 11

  # Define a function to note if restrictions are impacting the road or river route

  road.trader.restrictions <- function(x) {
    if (sum(x %in% "warning_restrictions" | x %in% "closed_restrictions") > 1) {
      return("yes")
    } else {
      return("")
    }
  }

  # --------- 12

  # Define a function that notes if the route is impacted by movement restrictions

  road.feedback.restrictions <- function(x) {
    if (sum(x %in% "warning_restrictions" | x %in% "closed_restrictions") > 0) {
      return("yes")
    } else {
      return("")
    }
  }

  # --------- 13

  # Define supply market aggregation function. The overall reponse is the modal answer (most frequently named supply market).

  mode <- function(x) {
    ux <- unique(x[!is.na(x)])
    # This checks to see if we have more than one mode (a tie), return blank if so.
    if (length(which(tabulate(match(x, ux)) == max(tabulate(match(x, ux))))) > 1) {
      if (class(x) == "logical") {
        return(as.logical("")) # Blanks are coerced to values in logical vectors, so we specifically identify columns with TRUE/FALSE (KoBo's select multiples) and output a "logical" blank.
      } else {
        return("NC")
      }
    } else {
      ux[which.max(tabulate(match(x, ux)))] ## This occurs if no tie, so we return the value which has max value
    }
  }

  # --------- 14

  # Define the function to aggregate marketplace level feedback data on availability to the location level:

  feedback.availability <- function(x) {
    # ux <- unique(x[!is.na(x)])
    if (sum(x %in% "1") > 0) {
      return("1")
    } else {
      return("0")
    }
  }

  # --------- 15



  # ============================================== QUOTATIONS ==========================================================

  # This section calculates the number of prices that were collected for each item per location.

  # First, we indicate which variables are used for the aggregation (select). Then we specify how the output data is grouped (group_by), and finally, we define,
  # which function to apply (summarise_all).

  quotation <- jmmi.raw %>%
    select(
      state, county, location, location2, sorghum_grain_price, maize_grain_price, wheat_flour_price, rice_price,
      groundnuts_price, beans_price, sugar_price, salt_price, cooking_oil_price, soap_price,
      jerrycan_price, mosquito_net_price, exercise_book_price, blanket_price, cooking_pot_price,
      plastic_sheet_price, pole_price, firewood_price, charcoal_price, goat_price, chicken_price,
      grinding_costs_ssp, grinding_costs_maize_calc,
      usd_price_buy, sdg_price_buy, etb_price_buy, ugx_price_buy, kes_price_buy, cdf_price_buy,
      xaf_price_buy,
      rubber_rope_price, kanga_price, solar_lamp_price,
      # aqua_tab_price,
      plastic_bucket_price, sanitary_pads_price, pen_price, pencil_price, rubber_price, sharpener_price,
      # water_price_unit_ssp
      sleeping_mat_price, bamboo_price, underwear_price, school_bag_price, bra_price, grass_price
    ) %>%
    group_by(state, county, location, location2) %>%
    summarise(across(everything(), ~ sum(!is.na(.))))

  # The following code identifies if there is only one quotation available and if this quotation is measured
  # using a JMMI mug it flags the location for a check up. This is important as measuring with a JMMI mug can create outliers
  # only dry foods will be measured using a JMMI mug so only these are selected

  # Select the quotatiosn

  quotation_check <- quotation %>%
    select(
      sorghum_grain_price, maize_grain_price, wheat_flour_price,
      rice_price, beans_price, sugar_price, salt_price
    )

  # Select relevant units and prices

  unit_price <- jmmi.raw %>%
    select(
      location, location2, sorghum_grain_unit, sorghum_grain_price_unit_ssp, maize_grain_unit, maize_grain_price_unit_ssp,
      wheat_flour_unit, wheat_flour_price_unit_ssp, rice_unit, rice_price_unit_ssp,
      beans_unit, beans_price_unit_ssp, sugar_unit, sugar_price_unit_ssp,
      salt_unit, salt_price_unit_ssp
    )

  # Create variables for each of the national median prices for dry foods

  sorghum_median <- median(jmmi$sorghum_grain_price_unit_ssp, na.rm = TRUE)
  maize_median <- median(jmmi$maize_grain_price_unit_ssp, na.rm = TRUE)
  wheat_flour_median <- median(jmmi$wheat_flour_price_unit_ssp, na.rm = TRUE)
  rice_median <- median(jmmi$rice_price_unit_ssp, na.rm = TRUE)
  beans_median <- median(jmmi$beans_price_unit_ssp, na.rm = TRUE)
  salt_median <- median(jmmi$salt_price_unit_ssp, na.rm = TRUE)
  sugar_median <- median(jmmi$sugar_price_unit_ssp, na.rm = TRUE)

  # Join the number of quotations, prices and units and flag any prices that have only
  # one quotation, are two times over or under the national median and use the JMMI mug as a unit

  # --------- 1

  quotation_check_unit <- left_join(unit_price, quotation_check) %>%
    mutate_at(c(
      "sorghum_grain_price_unit_ssp", "maize_grain_price_unit_ssp", "wheat_flour_price_unit_ssp",
      "rice_price_unit_ssp", "beans_price_unit_ssp", "sugar_price_unit_ssp", "salt_price_unit_ssp"
    ), as.numeric) %>%
    mutate(
      sorghum_check = ifelse(sorghum_grain_price == 1 & (sorghum_grain_price_unit_ssp > 2 * sorghum_median | sorghum_grain_price_unit_ssp < .5 * sorghum_median) & sorghum_grain_unit %in% "mug_jmmi", "!", ""),
      maize_check = ifelse(maize_grain_price == 1 & (maize_grain_price_unit_ssp > 2 * maize_median | maize_grain_price_unit_ssp < .5 * maize_median) & maize_grain_unit %in% "mug_jmmi", "!", ""),
      wheat_flour_check = ifelse(wheat_flour_price == 1 & (wheat_flour_price_unit_ssp > 2 * wheat_flour_median | wheat_flour_price_unit_ssp < .5 * wheat_flour_median) & wheat_flour_unit %in% "mug_jmmi", "!", ""),
      rice_check = ifelse(rice_price == 1 & (rice_price_unit_ssp > 2 * rice_median | rice_price_unit_ssp < .5 * rice_median) & rice_unit %in% "mug_jmmi", "!", ""),
      beans_check = ifelse(beans_price == 1 & (beans_price_unit_ssp > 2 * beans_median | beans_price_unit_ssp < .5 * beans_median) & beans_unit %in% "mug_jmmi", "!", ""),
      sugar_check = ifelse(sugar_price == 1 & (sugar_price_unit_ssp > 2 * sugar_median | sugar_price_unit_ssp < .5 * sugar_median) & sugar_unit %in% "mug_jmmi", "!", ""),
      salt_check = ifelse(salt_price == 1 & (salt_price_unit_ssp > 2 * salt_median | salt_price_unit_ssp < .5 * salt_median) & salt_unit %in% "mug_jmmi", "!", "")
    ) %>%
    select(state, county, location, location2, sorghum_check, maize_check, wheat_flour_check, rice_check, beans_check, sugar_check, salt_check) %>%
    group_by(state, county, location, location2) %>%
    summarise_all(quote_check) %>%
    filter(!is.na(state))


  # ============================================== AVAILABILITY ==========================================================

  # run the aggregation based on the availability function:

  # --------- 2

  availability <- jmmi %>%
    select(
      state, county, location, sorghum_grain_available, maize_grain_available, wheat_flour_available, rice_available,
      groundnuts_available, beans_available, sugar_available, salt_available, cooking_oil_available, soap_available,
      jerrycan_available, mosquito_net_available, exercise_book_available, blanket_available, cooking_pot_available,
      plastic_sheet_available, pole_available, firewood_available, charcoal_available, goat_available, chicken_available,
      usd_available, sdg_available, etb_available, ugx_available, kes_available, cdf_available, xaf_available,
      rubber_rope_available, kanga_available, solar_lamp_available,
      # aqua_tab_available,
      plastic_bucket_available, sanitary_pads_available,
      pen_available, pencil_available, rubber_available, sharpener_available,
      sleeping_mat_available, bamboo_available, underwear_available, school_bag_available, bra_available, grass_available
      # water_available
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), availability))

  # ============================================== PRICES (retail) ==========================================================

  # Calculate the median for each item by location through the following aggregation function:

  median <- jmmi %>%
    select(
      state, county, location, sorghum_grain_price_unit_ssp, maize_grain_price_unit_ssp, wheat_flour_price_unit_ssp, rice_price_unit_ssp,
      groundnuts_price_unit_ssp, beans_price_unit_ssp, sugar_price_unit_ssp, salt_price_unit_ssp, cooking_oil_price_unit_ssp, soap_price_unit_ssp,
      jerrycan_price_unit_ssp, mosquito_net_price_unit_ssp, exercise_book_price_unit_ssp, blanket_price_unit_ssp, cooking_pot_price_unit_ssp,
      plastic_sheet_price_unit_ssp, pole_price_unit_ssp, firewood_price_unit_ssp, charcoal_price_unit_ssp, goat_price_unit_ssp, chicken_price_unit_ssp,
      grinding_costs_ssp,
      usd_price_ind, sdg_price_ind, etb_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit_ssp, kanga_price_unit_ssp, solar_lamp_price_unit_ssp,
      # aqua_tab_price_unit_ssp,
      plastic_bucket_price_unit_ssp, sanitary_pads_price_unit_ssp, pen_price_unit_ssp, pencil_price_unit_ssp, rubber_price_unit_ssp, sharpener_price_unit_ssp,
      sleeping_mat_price_unit_ssp, bamboo_price_unit_ssp, underwear_price_unit_ssp, school_bag_price_unit_ssp, bra_price_unit_ssp, grass_price_unit_ssp
      # water_price_unit_ssp
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))


  # Rename the column headers:

  median <- median %>%
    rename(
      State = state, County = county, Location = location, "Sorghum.grain" = sorghum_grain_price_unit_ssp, "Maize.grain" = maize_grain_price_unit_ssp,
      "Wheat.flour" = wheat_flour_price_unit_ssp, Rice = rice_price_unit_ssp, Groundnuts = groundnuts_price_unit_ssp, Beans = beans_price_unit_ssp,
      Sugar = sugar_price_unit_ssp, Salt = salt_price_unit_ssp, "Cooking.oil" = cooking_oil_price_unit_ssp, Soap = soap_price_unit_ssp, Jerrycan = jerrycan_price_unit_ssp,
      "Mosquito.net" = mosquito_net_price_unit_ssp, "Exercise.book" = exercise_book_price_unit_ssp, Blanket = blanket_price_unit_ssp, "Cooking.pot" = cooking_pot_price_unit_ssp,
      "Plastic.sheet" = plastic_sheet_price_unit_ssp, Pole = pole_price_unit_ssp, Firewood = firewood_price_unit_ssp, Charcoal = charcoal_price_unit_ssp, Goat = goat_price_unit_ssp,
      Chicken = chicken_price_unit_ssp, "Milling.costs" = grinding_costs_ssp, "USD" = usd_price_ind, "SDG" = sdg_price_ind,
      ETB = etb_price_ind, UGX = ugx_price_ind, KES = kes_price_ind, CDF = cdf_price_ind, XAF = xaf_price_ind,
      "Rubber.rope" = rubber_rope_price_unit_ssp, "Kanga" = kanga_price_unit_ssp, "Solar.lamp" = solar_lamp_price_unit_ssp,
      # "Aqua.tab" = aqua_tab_price_unit_ssp,
      "Plastic.bucket" = plastic_bucket_price_unit_ssp,
      "Sanitary.pad" = sanitary_pads_price_unit_ssp, "Pen" = pen_price_unit_ssp, "Pencil" = pencil_price_unit_ssp, "Rubber" = rubber_price_unit_ssp, "Sharpener" = sharpener_price_unit_ssp,
      "Sleeping.mat" = sleeping_mat_price_unit_ssp, "Bamboo" = bamboo_price_unit_ssp, "Underwear" = underwear_price_unit_ssp, "School.bag" = school_bag_price_unit_ssp, "Bra" = bra_price_unit_ssp,
      "Grass" = grass_price_unit_ssp
      # "Water" =  water_price_unit_ssp
    )


  # Calculate the median for each item in ETB by location through the following aggregation function:

  median.etb <- jmmi %>%
    filter(currency %in% "ETB") %>%
    select(
      state, county, location, sorghum_grain_price_unit, maize_grain_price_unit,
      wheat_flour_price_unit, rice_price_unit, groundnuts_price_unit,
      beans_price_unit, sugar_price_unit, salt_price_unit, cooking_oil_price_unit,
      soap_price_unit, jerrycan_price_unit, mosquito_net_price_unit, exercise_book_price_unit,
      blanket_price_unit, cooking_pot_price_unit, plastic_sheet_price_unit, pole_price_unit,
      firewood_price_unit, charcoal_price_unit, goat_price_unit, chicken_price_unit, grinding_costs_sorghum_calc,
      usd_price_ind, sdg_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit, kanga_price_unit, solar_lamp_price_unit,
      # aqua_tab_price_unit,
      plastic_bucket_price_unit,
      sanitary_pads_price_unit, pen_price_unit, pencil_price_unit, rubber_price_unit, sharpener_price_unit,
      sleeping_mat_price_unit, bamboo_price_unit, underwear_price_unit, school_bag_price_unit, bra_price_unit, grass_price_unit
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))

  # Rename the ETB price column headers:

  median.etb <- median.etb %>%
    rename(
      State = state, County = county, Location = location, "Sorghum.grain.etb" = sorghum_grain_price_unit, "Maize.grain.etb" = maize_grain_price_unit,
      "Wheat.flour.etb" = wheat_flour_price_unit, "Rice.etb" = rice_price_unit, "Groundnuts.etb" = groundnuts_price_unit, "Beans.etb" = beans_price_unit,
      "Sugar.etb" = sugar_price_unit, "Salt.etb" = salt_price_unit, "Cooking.oil.etb" = cooking_oil_price_unit, "Soap.etb" = soap_price_unit, "Jerrycan.etb" = jerrycan_price_unit,
      "Mosquito.net.etb" = mosquito_net_price_unit, "Exercise.book.etb" = exercise_book_price_unit, "Blanket.etb" = blanket_price_unit, "Cooking.pot.etb" = cooking_pot_price_unit,
      "Plastic.sheet.etb" = plastic_sheet_price_unit, "Pole.etb" = pole_price_unit, "Firewood.etb" = firewood_price_unit, "Charcoal.etb" = charcoal_price_unit, "Goat.etb" = goat_price_unit,
      "Chicken.etb" = chicken_price_unit, "Milling.costs.etb" = grinding_costs_sorghum_calc, "USD.etb" = usd_price_ind, "SDG.etb" = sdg_price_ind,
      "UGX.etb" = ugx_price_ind, "KES.etb" = kes_price_ind, "CDF.etb" = cdf_price_ind, "XAF.etb" = xaf_price_ind,
      "Rubber.rope.etb" = rubber_rope_price_unit, "Kanga.etb" = kanga_price_unit, "Solar.lamp.etb" = solar_lamp_price_unit,
      # "Aqua.tab.etb" = aqua_tab_price_unit,
      "Plastic.bucket.etb" = plastic_bucket_price_unit,
      "Sanitary.pad.etb" = sanitary_pads_price_unit, "Pen.etb" = pen_price_unit, "Pencil.etb" = pencil_price_unit, "Rubber.etb" = rubber_price_unit, "Sharpener.etb" = sharpener_price_unit,
      "Sleeping.mat.etb" = sleeping_mat_price_unit, "Bamboo.etb" = bamboo_price_unit, "Underwear.etb" = underwear_price_unit, "School.bag.etb" = school_bag_price_unit, "Bra.etb" = bra_price_unit,
      "Grass.etb" = grass_price_unit
    )

  # Calculate the maximum prices per item and location:

  max <- jmmi %>%
    select(
      state, county, location, sorghum_grain_price_unit_ssp, maize_grain_price_unit_ssp, wheat_flour_price_unit_ssp, rice_price_unit_ssp,
      groundnuts_price_unit_ssp, beans_price_unit_ssp, sugar_price_unit_ssp, salt_price_unit_ssp, cooking_oil_price_unit_ssp, soap_price_unit_ssp,
      jerrycan_price_unit_ssp, mosquito_net_price_unit_ssp, exercise_book_price_unit_ssp, blanket_price_unit_ssp, cooking_pot_price_unit_ssp,
      plastic_sheet_price_unit_ssp, pole_price_unit_ssp, firewood_price_unit_ssp, charcoal_price_unit_ssp, goat_price_unit_ssp, chicken_price_unit_ssp,
      grinding_costs_ssp, usd_price_ind, sdg_price_ind, etb_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit_ssp, kanga_price_unit_ssp, solar_lamp_price_unit_ssp,
      # aqua_tab_price_unit_ssp,
      plastic_bucket_price_unit_ssp,
      sanitary_pads_price_unit_ssp, pen_price_unit_ssp, pencil_price_unit_ssp, rubber_price_unit_ssp, sharpener_price_unit_ssp,
      # water_price_unit_ssp,
      sleeping_mat_price_unit_ssp, bamboo_price_unit_ssp, underwear_price_unit_ssp, school_bag_price_unit_ssp, bra_price_unit_ssp, grass_price_unit_ssp
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ max(., na.rm = TRUE)))

  # Calculate the maximum ETB prices per item and location:

  max.etb <- jmmi %>%
    filter(currency %in% "ETB") %>%
    select(
      state, county, location, sorghum_grain_price_unit, maize_grain_price_unit,
      wheat_flour_price_unit, rice_price_unit, groundnuts_price_unit,
      beans_price_unit, sugar_price_unit, salt_price_unit, cooking_oil_price_unit,
      soap_price_unit, jerrycan_price_unit, mosquito_net_price_unit, exercise_book_price_unit,
      blanket_price_unit, cooking_pot_price_unit, plastic_sheet_price_unit, pole_price_unit,
      firewood_price_unit, charcoal_price_unit, goat_price_unit,
      chicken_price_unit, grinding_costs_sorghum_calc,
      usd_price_ind, sdg_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit, kanga_price_unit, solar_lamp_price_unit,
      # aqua_tab_price_unit,
      plastic_bucket_price_unit,
      sanitary_pads_price_unit, pen_price_unit, pencil_price_unit, rubber_price_unit, sharpener_price_unit,
      sleeping_mat_price_unit, bamboo_price_unit, underwear_price_unit, school_bag_price_unit, bra_price_unit, grass_price_unit
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ max(., na.rm = TRUE)))


  # Calculate the minimum prices per item and location:

  min <- jmmi %>%
    select(
      state, county, location, sorghum_grain_price_unit_ssp, maize_grain_price_unit_ssp, wheat_flour_price_unit_ssp, rice_price_unit_ssp,
      groundnuts_price_unit_ssp, beans_price_unit_ssp, sugar_price_unit_ssp, salt_price_unit_ssp, cooking_oil_price_unit_ssp, soap_price_unit_ssp,
      jerrycan_price_unit_ssp, mosquito_net_price_unit_ssp, exercise_book_price_unit_ssp, blanket_price_unit_ssp, cooking_pot_price_unit_ssp,
      plastic_sheet_price_unit_ssp, pole_price_unit_ssp, firewood_price_unit_ssp, charcoal_price_unit_ssp, goat_price_unit_ssp, chicken_price_unit_ssp,
      grinding_costs_ssp, usd_price_ind, sdg_price_ind, etb_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit_ssp, kanga_price_unit_ssp, solar_lamp_price_unit_ssp,
      # aqua_tab_price_unit_ssp,
      plastic_bucket_price_unit_ssp,
      sanitary_pads_price_unit_ssp, pen_price_unit_ssp, pencil_price_unit_ssp, rubber_price_unit_ssp, sharpener_price_unit_ssp,
      # water_price_unit_ssp
      sleeping_mat_price_unit_ssp, bamboo_price_unit_ssp, underwear_price_unit_ssp, school_bag_price_unit_ssp, bra_price_unit_ssp, grass_price_unit_ssp
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ min(., na.rm = TRUE)))

  # Calculate the minimum prices per item and location:

  min.etb <- jmmi %>%
    filter(currency %in% "ETB") %>%
    select(
      state, county, location, sorghum_grain_price_unit, maize_grain_price_unit,
      wheat_flour_price_unit, rice_price_unit, groundnuts_price_unit,
      beans_price_unit, sugar_price_unit, salt_price_unit, cooking_oil_price_unit,
      soap_price_unit, jerrycan_price_unit, mosquito_net_price_unit, exercise_book_price_unit,
      blanket_price_unit, cooking_pot_price_unit, plastic_sheet_price_unit, pole_price_unit,
      firewood_price_unit, charcoal_price_unit, goat_price_unit,
      chicken_price_unit, grinding_costs_sorghum_calc,
      usd_price_ind, sdg_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit, kanga_price_unit, solar_lamp_price_unit,
      # aqua_tab_price_unit,
      plastic_bucket_price_unit,
      sanitary_pads_price_unit, pen_price_unit, pencil_price_unit, rubber_price_unit, sharpener_price_unit,
      # water_price_unit_ssp
      sleeping_mat_price_unit, bamboo_price_unit, underwear_price_unit, school_bag_price_unit, bra_price_unit, grass_price_unit
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ min(., na.rm = TRUE)))

  # In the next step, we filter out all the relevant price columns and save them in a seperate data frame (to feed the "all_prices" tab in the analysis worksheet):

  all_prices <- jmmi %>%
    select(
      location, marketplace, entry, size, currency, sorghum_grain_type, sorghum_grain_unit, sorghum_grain_price, sorghum_grain_price_unit_ssp, maize_grain_unit,
      maize_grain_price, maize_grain_price_unit_ssp, wheat_flour_unit, wheat_flour_price, wheat_flour_price_unit_ssp, rice_unit, rice_price,
      rice_price_unit_ssp, groundnuts_unit, groundnuts_price, groundnuts_price_unit_ssp, beans_type, beans_unit, beans_price, beans_price_unit_ssp,
      sugar_type, sugar_unit, sugar_price, sugar_price_unit_ssp, salt_unit, salt_price, salt_price_unit_ssp, cooking_oil_type, cooking_oil_unit,
      cooking_oil_price, cooking_oil_price_unit_ssp,
      # water_price_unit_ssp,
      soap_type, soap_price, soap_price_unit_ssp, jerrycan_price_unit_ssp, mosquito_net_price_unit_ssp,
      exercise_book_price_unit, blanket_price_unit, cooking_pot_price_unit, plastic_sheet_price_unit, pole_price_unit, firewood_price_unit_ssp,
      charcoal_size, charcoal_price, charcoal_price_unit_ssp, goat_price_unit_ssp, chicken_price_unit_ssp, grinding_costs_ssp, grinding_costs_sorghum_calc_ssp,
      grinding_costs_maize_calc_ssp, usd_price_buy, usd_price_sell, sdg_price_buy, sdg_price_sell, etb_price_buy, etb_price_sell,
      ugx_price_buy, ugx_price_sell, kes_price_buy, kes_price_sell, cdf_price_buy, cdf_price_sell, xaf_price_buy, xaf_price_sell, rubber_rope_price_unit_ssp, kanga_price_unit_ssp, solar_lamp_price_unit_ssp,
      # aqua_tab_price_unit_ssp,
      plastic_bucket_price_unit_ssp, sanitary_pads_price_unit_ssp, pen_price_unit_ssp, pencil_price_unit_ssp, rubber_price_unit_ssp, sharpener_price_unit_ssp,
      sleeping_mat_price_unit_ssp, bamboo_price_unit_ssp, underwear_price_unit_ssp, school_bag_price_unit_ssp, bra_price_unit_ssp, grass_price_unit_ssp
    )


  # ============================================== PRICES (wholesale) ==========================================================


  # Apply the median aggregation function to the wholesale prices:

  median.wholesale <- jmmi %>%
    select(state, county, location, sorghum_grain_wholesale_price_unit_ssp, maize_grain_wholesale_price_unit_ssp, beans_wholesale_price_unit_ssp, sugar_wholesale_price_unit_ssp) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))


  # Rename the columns:

  median.wholesale <- median.wholesale %>%
    rename(
      "State" = state, "County" = county, "Location" = location, "Sorghum.grain" = sorghum_grain_wholesale_price_unit_ssp, "Maize.grain" = maize_grain_wholesale_price_unit_ssp,
      "Beans" = beans_wholesale_price_unit_ssp, "Sugar" = sugar_wholesale_price_unit_ssp
    )


  # Filter our all the relevant price columns and save them in a seperate data frame (to feed the "all_prices_wholesale" tab in the analysis worksheet):

  all_prices.wholesale <- jmmi %>%
    select(
      location, marketplace, entry, currency, sorghum_grain_wholesale_type, sorghum_grain_wholesale_unit, sorghum_grain_wholesale_price, sorghum_grain_wholesale_price_unit_ssp,
      maize_grain_wholesale_unit, maize_grain_wholesale_price, maize_grain_wholesale_price_unit_ssp, beans_wholesale_type, beans_wholesale_unit, beans_wholesale_price,
      beans_wholesale_price_unit_ssp, sugar_wholesale_type, sugar_wholesale_unit, sugar_wholesale_price, sugar_wholesale_price_unit_ssp
    )


  # ============================================== EXPECTATIONS ==========================================================

  # Apply the price expectation aggregation function

  # --------- 3

  expectation.price <- jmmi %>%
    select(state, county, location, food_expectation_price_3months, nfi_expectation_price_3months) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), expectation.price))


  # ============================================== STOCKS ==========================================================


  # Apply the restock aggregation function:

  # --------- 4

  restock <- jmmi %>%
    select(
      state, county, location, sorghum_grain_restock, maize_grain_restock, wheat_flour_restock, rice_restock,
      groundnuts_restock, beans_restock, sugar_restock, salt_restock, cooking_oil_restock, soap_restock,
      pen_available_restock, pencil_available_restock, rubber_available_restock, sharpener_available_restock, rubber_rope_available_restock,
      kanga_available_restock, solar_lamp_available_restock,
      # aqua_tab_available_restock,
      plastic_bucket_available_restock, sanitary_pads_available_restock,
      jerrycan_restock, mosquito_net_restock, exercise_book_restock, blanket_restock, cooking_pot_restock,
      plastic_sheet_restock,
      sleeping_mat_restock, underwear_available_restock, school_bag_available_restock, bra_available_restock
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), restock))


  # Apply the restocked aggregation function:

  # --------- 5

  restocked <- jmmi %>%
    select(
      state, county, location, sorghum_grain_restock_1month, maize_grain_restock_1month, wheat_flour_restock_1month, rice_restock_1month,
      groundnuts_restock_1month, beans_restock_1month, sugar_restock_1month, salt_restock_1month, cooking_oil_restock_1month, soap_restock_1month,
      pen_available_restock_1month, pencil_available_restock_1month, rubber_available_restock_1month, sharpener_available_restock_1month, rubber_rope_available_restock_1month,
      kanga_available_restock_1month, solar_lamp_available_restock_1month,
      # aqua_tab_available_restock_1month,
      plastic_bucket_available_restock_1month, sanitary_pads_available_restock_1month,
      jerrycan_restock_1month, mosquito_net_restock_1month, exercise_book_restock_1month, blanket_restock_1month, cooking_pot_restock_1month,
      plastic_sheet_restock_1month,
      sleeping_mat_restock_1month, underwear_available_restock_1month, school_bag_available_restock_1month, bra_available_restock_1month
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), restocked))


  # Apply the median aggregation function to stock levels:

  stock_level <- jmmi %>%
    select(
      state, county, location, sorghum_grain_stock_current, maize_grain_stock_current, wheat_flour_stock_current, rice_stock_current,
      groundnuts_stock_current, beans_stock_current, sugar_stock_current, salt_stock_current, cooking_oil_stock_current, soap_stock_current,
      pen_available_stock_current, pencil_available_stock_current, rubber_available_stock_current, sharpener_available_stock_current,
      rubber_rope_available_stock_current, kanga_available_stock_current, solar_lamp_available_stock_current,
      # aqua_tab_available_stock_current,
      plastic_bucket_available_stock_current, sanitary_pads_available_stock_current,
      jerrycan_stock_current, mosquito_net_stock_current, exercise_book_stock_current, blanket_stock_current, cooking_pot_stock_current,
      plastic_sheet_stock_current,
      sleeping_mat_stock_current, underwear_available_stock_current, school_bag_available_stock_current, bra_available_stock_current
    ) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))


  # RESTOCK DURATION

  # Filter out all traders that restocked food items from a wholesaler in the same location:
  restock_duration_food_local <- jmmi %>% filter(food_supplier_local_same == "no")

  # Apply the median function:
  restock_duration_food_local <- restock_duration_food_local %>%
    select(state, county, location, food_supplier_local_duration) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))

  # Filter out all traders that restocked food items from a wholesaler in the same location:
  restock_duration_food_imported <- jmmi %>% filter(food_supplier_imported_same == "no")

  # Apply the median function:
  restock_duration_food_imported <- restock_duration_food_imported %>%
    select(state, county, location, food_supplier_imported_duration) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))


  # Filter out all traders that restocked food items from a wholesaler in the same location:
  restock_duration_nfi <- jmmi %>% filter(nfi_supplier_same == "no")

  # Apply the median function:
  restock_duration_nfi <- restock_duration_nfi %>%
    select(state, county, location, nfi_supplier_duration) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))

  # Join food and NFI duration dataframes
  restock_duration <- full_join(restock_duration_food_local, restock_duration_food_imported)
  restock_duration <- full_join(restock_duration, restock_duration_nfi)
  restock_duration <- restock_duration %>% arrange(.by_group = TRUE)

  # Run the median function over the location medians to get the overall median
  restock_duration_overall <- restock_duration %>%
    ungroup() %>%
    select(food_supplier_local_duration, food_supplier_imported_duration, nfi_supplier_duration) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))


  # Filter out all relevant stock indicators and save them in seperate data frame (for all_stocks tab in analysis worksheet):

  all_stocks <- jmmi %>%
    select(
      location, entry, size, sorghum_grain_restock_1month, sorghum_grain_stock_current, sorghum_grain_restock, maize_grain_restock_1month, maize_grain_stock_current,
      maize_grain_restock, wheat_flour_restock_1month, wheat_flour_stock_current, wheat_flour_restock, rice_restock_1month, rice_stock_current, rice_restock,
      groundnuts_restock_1month, groundnuts_stock_current, groundnuts_restock, beans_restock_1month, beans_stock_current, beans_restock, sugar_restock_1month,
      sugar_stock_current, sugar_restock, salt_restock_1month, salt_stock_current, salt_restock, cooking_oil_restock_1month, cooking_oil_stock_current,
      cooking_oil_restock, soap_restock_1month, soap_stock_current, soap_restock, jerrycan_restock_1month, jerrycan_stock_current, jerrycan_restock,
      pen_available_restock, pen_available_restock_1month, pen_available_stock_current, pencil_available_restock, pencil_available_restock_1month, pencil_available_stock_current,
      rubber_available_restock, rubber_available_restock_1month, rubber_available_stock_current, sharpener_available_restock, sharpener_available_restock_1month, sharpener_available_stock_current,
      rubber_rope_available_restock, rubber_rope_available_restock_1month, rubber_rope_available_stock_current, kanga_available_restock, kanga_available_restock_1month, kanga_available_stock_current,
      solar_lamp_available_restock, solar_lamp_available_restock_1month, solar_lamp_available_stock_current,
      # aqua_tab_available_restock,aqua_tab_available_restock_1month,aqua_tab_available_stock_current,
      plastic_bucket_available_restock, plastic_bucket_available_restock_1month, plastic_bucket_available_stock_current, sanitary_pads_available_restock, sanitary_pads_available_restock_1month, sanitary_pads_available_stock_current,
      mosquito_net_restock_1month, mosquito_net_stock_current, mosquito_net_restock, exercise_book_restock_1month, exercise_book_stock_current, exercise_book_restock,
      blanket_restock_1month, blanket_stock_current, blanket_restock, cooking_pot_restock_1month, cooking_pot_stock_current, cooking_pot_restock,
      plastic_sheet_restock_1month, plastic_sheet_stock_current, plastic_sheet_restock,
      sleeping_mat_restock_1month, sleeping_mat_stock_current, sleeping_mat_restock, underwear_available_restock, underwear_available_restock_1month, underwear_available_stock_current, school_bag_available_restock,
      school_bag_available_restock_1month, school_bag_available_stock_current, bra_available_restock, bra_available_restock_1month, bra_available_stock_current
    )
  # ============================== WHOLESALER RESTOCK AND TRADE VOLUME =============================================

  # Take the mdian volum of stock for a wholsaler according to wholesalr sizee
  trade_volume_wholesale <- jmmi %>%
    select(
      state, county, location, size_wholesale,
      maize_grain_wholesale_quantity, maize_grain_wholesale_stock_current,
      sorghum_grain_wholesale_quantity, sorghum_grain_wholesale_stock_current,
      beans_wholesale_quantity, beans_wholesale_stock_current,
      sugar_wholesale_quantity, sugar_wholesale_stock_current
    ) %>%
    filter(size_wholesale != "") %>%
    group_by(state, county, location, size_wholesale) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))

  wholesaler_numbers <- jmmi


  # ============================================== BORDERS ==========================================================

  # The following script summarises whether a certain border crossing is subject to quarantine measures.

  # --------- 7

  border.trader.quarantine <- jmmi %>%
    select(
      border_crossings_narus_01, border_crossings_biralopuse_02, border_crossings_trestenya_03,
      border_crossings_labone_04, border_crossings_ngomoromo_05, border_crossings_mugali_06,
      border_crossings_nimule_07, border_crossings_jale_08, border_crossings_kaya_09,
      border_crossings_bazi_10, border_crossings_dimo_11, border_crossings_nabiapai_12,
      border_crossings_sakure_13, border_crossings_bagugu_14, border_crossings_ezo_15, border_crossings_riyubu_16,
      border_crossings_raja_17, border_crossings_kiir_adem_18, border_crossings_majok_19, border_crossings_abyei_20,
      border_crossings_tishwin_21, border_crossings_bongki_22, border_crossings_jau_23, border_crossings_alel_24,
      border_crossings_tallodi_25, border_crossings_renk_26, border_crossings_yabus_27, border_crossings_pagak_28,
      border_crossings_jikou_29, border_crossings_matar_30, border_crossings_jikmir_31, border_crossings_akobo_32,
      border_crossings_pochala_33
    ) %>%
    summarise_all(border.trader.quarantine)

  # Apply border aggregation function:

  # --------- 6

  border.trader <- jmmi %>%
    select(
      border_crossings_narus_01, border_crossings_biralopuse_02, border_crossings_trestenya_03,
      border_crossings_labone_04, border_crossings_ngomoromo_05, border_crossings_mugali_06,
      border_crossings_nimule_07, border_crossings_jale_08, border_crossings_kaya_09,
      border_crossings_bazi_10, border_crossings_dimo_11, border_crossings_nabiapai_12,
      border_crossings_sakure_13, border_crossings_bagugu_14, border_crossings_ezo_15, border_crossings_riyubu_16,
      border_crossings_raja_17, border_crossings_kiir_adem_18, border_crossings_majok_19, border_crossings_abyei_20,
      border_crossings_tishwin_21, border_crossings_bongki_22, border_crossings_jau_23, border_crossings_alel_24,
      border_crossings_tallodi_25, border_crossings_renk_26, border_crossings_yabus_27, border_crossings_pagak_28,
      border_crossings_jikou_29, border_crossings_matar_30, border_crossings_jikmir_31, border_crossings_akobo_32,
      border_crossings_pochala_33
    ) %>%
    summarise(across(everything(), border.trader))

  # Take the median for how long extra it takes to stock due to quarantine issues.

  border.trader.quarantine.restock <- jmmi %>%
    select(ends_with("_01")) %>%
    select(-border_crossings_narus_01) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))

  # Make sure the names match so they can join with the other datasets properly

  border.names <- names(border.trader)
  border.length <- length(border.trader.quarantine.restock)
  names(border.trader.quarantine.restock)[1:border.length] <- border.names
  border.trader.quarantine.restock[, ] <- lapply(border.trader.quarantine.restock[, ], as.character)


  # Apply the border (feedback) function to the data:

  # --------- 8

  border.feedback <- feedback %>%
    select(
      border_crossings_narus_01, border_crossings_biralopuse_02, border_crossings_trestenya_03,
      border_crossings_labone_04, border_crossings_ngomoromo_05, border_crossings_mugali_06,
      border_crossings_nimule_07, border_crossings_jale_08, border_crossings_kaya_09,
      border_crossings_bazi_10, border_crossings_dimo_11, border_crossings_nabiapai_12,
      border_crossings_sakure_13, border_crossings_bagugu_14, border_crossings_ezo_15, border_crossings_riyubu_16,
      border_crossings_raja_17, border_crossings_kiir_adem_18, border_crossings_majok_19, border_crossings_abyei_20,
      border_crossings_tishwin_21, border_crossings_bongki_22, border_crossings_jau_23, border_crossings_alel_24,
      border_crossings_tallodi_25, border_crossings_renk_26, border_crossings_yabus_27
    ) %>%
    summarise_all(border.feedback)



  # Join the aggregates from the trader questionnaire with the ones from the feedback form for export:

  border <- bind_rows(border.trader, border.feedback, border.trader.quarantine, border.trader.quarantine.restock)


  # ============================================== ROADS ==========================================================

  # Apply the road aggregation function:

  # --------- 9

  road.trader <- jmmi %>%
    select(
      supplier_road_nimule_juba_001, supplier_road_juba_terekeka_057, supplier_road_terakeka_mingkaman_058, supplier_road_mingkaman_yirol_003,
      supplier_road_yirol_akot_059, supplier_road_akot_rumbek_060, supplier_road_juba_mundri_061, supplier_road_mundri_rumbek_062, supplier_road_rumbek_maper_107,
      supplier_road_rumbek_cueibet_063, supplier_road_cueibet_tonj_064, supplier_road_tonj_wau_065, supplier_road_wau_aweil_007, supplier_road_wau_deimzubier_130,
      supplier_road_deimzubier_raja_131, supplier_road_aweil_gokmachar_direct_009, supplier_road_aweil_gokmachar_ariath_044, supplier_road_aweil_wanyjok_010,
      supplier_road_kiiradem_gokmachar_012, supplier_road_meram_wanyjok_013, supplier_road_ameit_wanyjok_direct_014, supplier_road_gogrial_wanyjok_015,
      supplier_road_ameit_wunrok_019, supplier_road_wunrok_gogrial_137, supplier_road_gogrial_kuajok_136, supplier_road_wau_kuajok_016,
      supplier_road_ameit_abiemnhom_067, supplier_road_abiemnhom_mayom_068, supplier_road_mayom_rubkona_069, supplier_road_rubkona_bentiu_070,
      supplier_road_juba_mangalla_127, supplier_road_mangalla_gemmaiza_128, supplier_road_gemmaiza_bor_129, supplier_road_bor_pibor_028,
      supplier_road_bor_akobo_025, supplier_road_bor_panyagor_023, supplier_road_panyagor_puktap_047, supplier_road_puktap_dukpadiet_071,
      supplier_road_dukpadiet_yuai_072, supplier_road_dukpadiet_ayod_076, supplier_road_yuai_pieri_077, supplier_road_lankien_waat_073,
      supplier_road_dukpadiet_waat_126, supplier_road_waat_akobo_074, # supplier_road_dukpadiet_mwottot_046,
      supplier_road_pibor_akobo_026,
      supplier_road_narus_pochala_029, supplier_road_narus_boma_081, supplier_road_renk_paloich_030, supplier_road_paloich_maban_031, supplier_road_paloich_melut_032,
      supplier_road_paloich_malakal_034, supplier_road_mundri_maridi_084, supplier_road_yei_maridi_037, supplier_road_morobo_yei_038, supplier_road_yei_dimo_140,
      supplier_road_morobo_bazi_123, supplier_road_morobo_kaya_124, supplier_road_maridi_ibba_138, supplier_road_ibba_yambio_139, supplier_road_yambio_nabiapai_141,
      supplier_road_yambio_sakure_142, supplier_road_nzara_bagugu_143, supplier_road_diabio_ezo_144, supplier_road_tambura_sourceyubu_145,
      supplier_road_yambio_tambura_040, supplier_road_tambura_nagero_132, supplier_road_nagero_wau_133, supplier_road_juba_torit_041, supplier_road_torit_kapoeta_042,
      supplier_road_kapoeta_narus_117, supplier_road_malakal_lankien_052, supplier_road_malakal_baliet_085, supplier_road_baliet_ulang_086,
      supplier_road_ulang_nasir_051, supplier_road_juba_lafon_089, supplier_road_torit_lafon_090, supplier_road_torit_magwi_091, supplier_road_magwi_labone_083,
      supplier_road_magwi_ngomoromo_125, supplier_road_torit_ikotos_092, supplier_road_ikotos_trestenya_108, supplier_road_ikotos_bira_122,
      supplier_road_juba_magwi_120, supplier_road_juba_kajokeji_093, supplier_road_kajokeji_jale_121, supplier_road_juba_lainya_134, supplier_road_lainya_yei_135,
      supplier_road_yirol_shambe_095, supplier_road_pagak_maiwut_109, supplier_road_pagak_mathiang_097, supplier_road_mathiang_guel_098, supplier_road_guit_leer_099,
      supplier_road_mayendit_panyijiar_100, supplier_road_rubkona_pariang_101, supplier_road_pariang_yida_102, supplier_road_pariang_jamjang_110,
      supplier_road_pariang_pamir_111, supplier_road_pariang_ajuongthok_112, supplier_road_tishwin_rubkona_103, supplier_road_bentiu_koch_104,
      supplier_road_bentiu_guit_105, supplier_road_koch_leer_106, supplier_road_tallodi_tonga_116, supplier_river_juba_bor_022, supplier_river_tiek_nyal_043,
      supplier_river_taiyar_ganylel_118, supplier_river_renk_melut_033, supplier_river_melut_malakal_035, supplier_river_malakal_ulang_055, supplier_river_ulang_dome_119,
      supplier_river_ulang_nasir_056, supplier_river_jikou_akobo_053, supplier_river_jikou_nasir_054, supplier_river_juba_malakal_113,
      supplier_river_juba_newfangak_114, supplier_river_juba_bentiu_115, supplier_road_gumuruk_mangalla_150,
    ) %>%
    summarise(across(everything(), road.trader))

  # The following uses the road.trader.restriction function to analyse whether any roads are shut due to movement restrictions

  # --------- 11

  road.trader.restrictions <- jmmi %>%
    select(
      supplier_road_nimule_juba_001, supplier_road_juba_terekeka_057, supplier_road_terakeka_mingkaman_058, supplier_road_mingkaman_yirol_003,
      supplier_road_yirol_akot_059, supplier_road_akot_rumbek_060, supplier_road_juba_mundri_061, supplier_road_mundri_rumbek_062, supplier_road_rumbek_maper_107,
      supplier_road_rumbek_cueibet_063, supplier_road_cueibet_tonj_064, supplier_road_tonj_wau_065, supplier_road_wau_aweil_007, supplier_road_wau_deimzubier_130,
      supplier_road_deimzubier_raja_131, supplier_road_aweil_gokmachar_direct_009, supplier_road_aweil_gokmachar_ariath_044, supplier_road_aweil_wanyjok_010,
      supplier_road_kiiradem_gokmachar_012, supplier_road_meram_wanyjok_013, supplier_road_ameit_wanyjok_direct_014, supplier_road_gogrial_wanyjok_015,
      supplier_road_ameit_wunrok_019, supplier_road_wunrok_gogrial_137, supplier_road_gogrial_kuajok_136, supplier_road_wau_kuajok_016,
      supplier_road_ameit_abiemnhom_067, supplier_road_abiemnhom_mayom_068, supplier_road_mayom_rubkona_069, supplier_road_rubkona_bentiu_070,
      supplier_road_juba_mangalla_127, supplier_road_mangalla_gemmaiza_128, supplier_road_gemmaiza_bor_129, supplier_road_bor_pibor_028,
      supplier_road_bor_akobo_025, supplier_road_bor_panyagor_023, supplier_road_panyagor_puktap_047, supplier_road_puktap_dukpadiet_071,
      supplier_road_dukpadiet_yuai_072, supplier_road_dukpadiet_ayod_076, supplier_road_yuai_pieri_077, supplier_road_lankien_waat_073,
      supplier_road_dukpadiet_waat_126, supplier_road_waat_akobo_074, # supplier_road_dukpadiet_mwottot_046,
      supplier_road_pibor_akobo_026,
      supplier_road_narus_pochala_029, supplier_road_narus_boma_081, supplier_road_renk_paloich_030, supplier_road_paloich_maban_031, supplier_road_paloich_melut_032,
      supplier_road_paloich_malakal_034, supplier_road_mundri_maridi_084, supplier_road_yei_maridi_037, supplier_road_morobo_yei_038, supplier_road_yei_dimo_140,
      supplier_road_morobo_bazi_123, supplier_road_morobo_kaya_124, supplier_road_maridi_ibba_138, supplier_road_ibba_yambio_139, supplier_road_yambio_nabiapai_141,
      supplier_road_yambio_sakure_142, supplier_road_nzara_bagugu_143, supplier_road_diabio_ezo_144, supplier_road_tambura_sourceyubu_145,
      supplier_road_yambio_tambura_040, supplier_road_tambura_nagero_132, supplier_road_nagero_wau_133, supplier_road_juba_torit_041, supplier_road_torit_kapoeta_042,
      supplier_road_kapoeta_narus_117, supplier_road_malakal_lankien_052, supplier_road_malakal_baliet_085, supplier_road_baliet_ulang_086,
      supplier_road_ulang_nasir_051, supplier_road_juba_lafon_089, supplier_road_torit_lafon_090, supplier_road_torit_magwi_091, supplier_road_magwi_labone_083,
      supplier_road_magwi_ngomoromo_125, supplier_road_torit_ikotos_092, supplier_road_ikotos_trestenya_108, supplier_road_ikotos_bira_122,
      supplier_road_juba_magwi_120, supplier_road_juba_kajokeji_093, supplier_road_kajokeji_jale_121, supplier_road_juba_lainya_134, supplier_road_lainya_yei_135,
      supplier_road_yirol_shambe_095, supplier_road_pagak_maiwut_109, supplier_road_pagak_mathiang_097, supplier_road_mathiang_guel_098, supplier_road_guit_leer_099,
      supplier_road_mayendit_panyijiar_100, supplier_road_rubkona_pariang_101, supplier_road_pariang_yida_102, supplier_road_pariang_jamjang_110,
      supplier_road_pariang_pamir_111, supplier_road_pariang_ajuongthok_112, supplier_road_tishwin_rubkona_103, supplier_road_bentiu_koch_104,
      supplier_road_bentiu_guit_105, supplier_road_koch_leer_106, supplier_road_tallodi_tonga_116, supplier_river_juba_bor_022, supplier_river_tiek_nyal_043,
      supplier_river_taiyar_ganylel_118, supplier_river_renk_melut_033, supplier_river_melut_malakal_035, supplier_river_malakal_ulang_055, supplier_river_ulang_dome_119,
      supplier_river_ulang_nasir_056, supplier_river_jikou_akobo_053, supplier_river_jikou_nasir_054, supplier_river_juba_malakal_113,
      supplier_river_juba_newfangak_114, supplier_river_juba_bentiu_115, supplier_road_gumuruk_mangalla_150
    ) %>%
    summarise(across(everything(), road.trader.restrictions))


  # Apply aggregation function:

  # --------- 10

  road.feedback <- feedback %>%
    select(
      supplier_road_nimule_juba_001, supplier_road_juba_terekeka_057, supplier_road_terakeka_mingkaman_058, supplier_road_mingkaman_yirol_003,
      supplier_road_yirol_akot_059, supplier_road_akot_rumbek_060, supplier_road_juba_mundri_061, supplier_road_mundri_rumbek_062, supplier_road_rumbek_maper_107,
      supplier_road_rumbek_cueibet_063, supplier_road_cueibet_tonj_064, supplier_road_tonj_wau_065, supplier_road_wau_aweil_007, supplier_road_wau_deimzubier_130,
      supplier_road_deimzubier_raja_131, supplier_road_aweil_gokmachar_direct_009, supplier_road_aweil_gokmachar_ariath_044, supplier_road_aweil_wanyjok_010,
      supplier_road_kiiradem_gokmachar_012, supplier_road_meram_wanyjok_013, supplier_road_ameit_wanyjok_direct_014, supplier_road_gogrial_wanyjok_015,
      supplier_road_ameit_wunrok_019, supplier_road_wunrok_gogrial_137, supplier_road_gogrial_kuajok_136, supplier_road_wau_kuajok_016,
      supplier_road_ameit_abiemnhom_067, supplier_road_abiemnhom_mayom_068, supplier_road_mayom_rubkona_069, supplier_road_rubkona_bentiu_070,
      supplier_road_juba_mangalla_127, supplier_road_mangalla_gemmaiza_128, supplier_road_gemmaiza_bor_129, supplier_road_bor_pibor_028,
      supplier_road_bor_akobo_025, supplier_road_bor_panyagor_023, supplier_road_panyagor_puktap_047, supplier_road_puktap_dukpadiet_071,
      supplier_road_dukpadiet_yuai_072, supplier_road_dukpadiet_ayod_076, supplier_road_yuai_pieri_077, supplier_road_lankien_waat_073,
      supplier_road_dukpadiet_waat_126, supplier_road_waat_akobo_074, # supplier_road_dukpadiet_mwottot_046,
      supplier_road_pibor_akobo_026,
      supplier_road_narus_pochala_029, supplier_road_narus_boma_081, supplier_road_renk_paloich_030, supplier_road_paloich_maban_031, supplier_road_paloich_melut_032,
      supplier_road_paloich_malakal_034, supplier_road_mundri_maridi_084, supplier_road_yei_maridi_037, supplier_road_morobo_yei_038, supplier_road_yei_dimo_140,
      supplier_road_morobo_bazi_123, supplier_road_morobo_kaya_124, supplier_road_maridi_ibba_138, supplier_road_ibba_yambio_139, supplier_road_yambio_nabiapai_141,
      supplier_road_yambio_sakure_142, supplier_road_nzara_bagugu_143, supplier_road_diabio_ezo_144, supplier_road_tambura_sourceyubu_145,
      supplier_road_yambio_tambura_040, supplier_road_tambura_nagero_132, supplier_road_nagero_wau_133, supplier_road_juba_torit_041, supplier_road_torit_kapoeta_042,
      supplier_road_kapoeta_narus_117, supplier_road_malakal_lankien_052, supplier_road_malakal_baliet_085, supplier_road_baliet_ulang_086,
      supplier_road_ulang_nasir_051, supplier_road_juba_lafon_089, supplier_road_torit_lafon_090, supplier_road_torit_magwi_091, supplier_road_magwi_labone_083,
      supplier_road_magwi_ngomoromo_125, supplier_road_torit_ikotos_092, supplier_road_ikotos_trestenya_108, supplier_road_ikotos_bira_122,
      supplier_road_juba_magwi_120, supplier_road_juba_kajokeji_093, supplier_road_kajokeji_jale_121, supplier_road_juba_lainya_134, supplier_road_lainya_yei_135,
      supplier_road_yirol_shambe_095, supplier_road_pagak_maiwut_109, supplier_road_pagak_mathiang_097, supplier_road_mathiang_guel_098, supplier_road_guit_leer_099,
      supplier_road_mayendit_panyijiar_100, supplier_road_rubkona_pariang_101, supplier_road_pariang_yida_102, supplier_road_pariang_jamjang_110,
      supplier_road_pariang_pamir_111, supplier_road_pariang_ajuongthok_112, supplier_road_tishwin_rubkona_103, supplier_road_bentiu_koch_104,
      supplier_road_bentiu_guit_105, supplier_road_koch_leer_106, supplier_road_tallodi_tonga_116, supplier_river_juba_bor_022, supplier_river_tiek_nyal_043,
      supplier_river_taiyar_ganylel_118, supplier_river_renk_melut_033, supplier_river_melut_malakal_035, supplier_river_malakal_ulang_055, supplier_river_ulang_dome_119,
      supplier_river_ulang_nasir_056, supplier_river_jikou_akobo_053, supplier_river_jikou_nasir_054, supplier_river_juba_malakal_113,
      supplier_river_juba_newfangak_114, supplier_river_juba_bentiu_115, supplier_road_gumuruk_mangalla_150
    ) %>%
    summarise(across(everything(), road.feedback))

  # The following uses the road.feedback.restriction function to analyse whether any roads are shut due to movement restrictions (for the feedback data)

  # --------- 12

  road.feedback.restrictions <- feedback %>%
    select(
      supplier_road_nimule_juba_001, supplier_road_juba_terekeka_057, supplier_road_terakeka_mingkaman_058, supplier_road_mingkaman_yirol_003,
      supplier_road_yirol_akot_059, supplier_road_akot_rumbek_060, supplier_road_juba_mundri_061, supplier_road_mundri_rumbek_062, supplier_road_rumbek_maper_107,
      supplier_road_rumbek_cueibet_063, supplier_road_cueibet_tonj_064, supplier_road_tonj_wau_065, supplier_road_wau_aweil_007, supplier_road_wau_deimzubier_130,
      supplier_road_deimzubier_raja_131, supplier_road_aweil_gokmachar_direct_009, supplier_road_aweil_gokmachar_ariath_044, supplier_road_aweil_wanyjok_010,
      supplier_road_kiiradem_gokmachar_012, supplier_road_meram_wanyjok_013, supplier_road_ameit_wanyjok_direct_014, supplier_road_gogrial_wanyjok_015,
      supplier_road_ameit_wunrok_019, supplier_road_wunrok_gogrial_137, supplier_road_gogrial_kuajok_136, supplier_road_wau_kuajok_016,
      supplier_road_ameit_abiemnhom_067, supplier_road_abiemnhom_mayom_068, supplier_road_mayom_rubkona_069, supplier_road_rubkona_bentiu_070,
      supplier_road_juba_mangalla_127, supplier_road_mangalla_gemmaiza_128, supplier_road_gemmaiza_bor_129, supplier_road_bor_pibor_028,
      supplier_road_bor_akobo_025, supplier_road_bor_panyagor_023, supplier_road_panyagor_puktap_047, supplier_road_puktap_dukpadiet_071,
      supplier_road_dukpadiet_yuai_072, supplier_road_dukpadiet_ayod_076, supplier_road_yuai_pieri_077, supplier_road_lankien_waat_073,
      supplier_road_dukpadiet_waat_126, supplier_road_waat_akobo_074, # supplier_road_dukpadiet_mwottot_046,
      supplier_road_pibor_akobo_026,
      supplier_road_narus_pochala_029, supplier_road_narus_boma_081, supplier_road_renk_paloich_030, supplier_road_paloich_maban_031, supplier_road_paloich_melut_032,
      supplier_road_paloich_malakal_034, supplier_road_mundri_maridi_084, supplier_road_yei_maridi_037, supplier_road_morobo_yei_038, supplier_road_yei_dimo_140,
      supplier_road_morobo_bazi_123, supplier_road_morobo_kaya_124, supplier_road_maridi_ibba_138, supplier_road_ibba_yambio_139, supplier_road_yambio_nabiapai_141,
      supplier_road_yambio_sakure_142, supplier_road_nzara_bagugu_143, supplier_road_diabio_ezo_144, supplier_road_tambura_sourceyubu_145,
      supplier_road_yambio_tambura_040, supplier_road_tambura_nagero_132, supplier_road_nagero_wau_133, supplier_road_juba_torit_041, supplier_road_torit_kapoeta_042,
      supplier_road_kapoeta_narus_117, supplier_road_malakal_lankien_052, supplier_road_malakal_baliet_085, supplier_road_baliet_ulang_086,
      supplier_road_ulang_nasir_051, supplier_road_juba_lafon_089, supplier_road_torit_lafon_090, supplier_road_torit_magwi_091, supplier_road_magwi_labone_083,
      supplier_road_magwi_ngomoromo_125, supplier_road_torit_ikotos_092, supplier_road_ikotos_trestenya_108, supplier_road_ikotos_bira_122,
      supplier_road_juba_magwi_120, supplier_road_juba_kajokeji_093, supplier_road_kajokeji_jale_121, supplier_road_juba_lainya_134, supplier_road_lainya_yei_135,
      supplier_road_yirol_shambe_095, supplier_road_pagak_maiwut_109, supplier_road_pagak_mathiang_097, supplier_road_mathiang_guel_098, supplier_road_guit_leer_099,
      supplier_road_mayendit_panyijiar_100, supplier_road_rubkona_pariang_101, supplier_road_pariang_yida_102, supplier_road_pariang_jamjang_110,
      supplier_road_pariang_pamir_111, supplier_road_pariang_ajuongthok_112, supplier_road_tishwin_rubkona_103, supplier_road_bentiu_koch_104,
      supplier_road_bentiu_guit_105, supplier_road_koch_leer_106, supplier_road_tallodi_tonga_116, supplier_river_juba_bor_022, supplier_river_tiek_nyal_043,
      supplier_river_taiyar_ganylel_118, supplier_river_renk_melut_033, supplier_river_melut_malakal_035, supplier_river_malakal_ulang_055, supplier_river_ulang_dome_119,
      supplier_river_ulang_nasir_056, supplier_river_jikou_akobo_053, supplier_river_jikou_nasir_054, supplier_river_juba_malakal_113,
      supplier_river_juba_newfangak_114, supplier_river_juba_bentiu_115, supplier_road_gumuruk_mangalla_150
    ) %>%
    summarise(across(everything(), road.feedback.restrictions))

  # Join aggregates from trader questionnaire and from feedback form for export:

  road <- bind_rows(road.trader, road.feedback, road.trader.restrictions, road.feedback.restrictions)


  # Filter out all road condition columns (for "all_roads" in analysis workbook):

  all_roads <- jmmi %>%
    select(
      location, entry, supplier_road_nimule_juba_001, supplier_road_juba_terekeka_057, supplier_road_terakeka_mingkaman_058, supplier_road_mingkaman_yirol_003,
      supplier_road_yirol_akot_059, supplier_road_akot_rumbek_060, supplier_road_juba_mundri_061, supplier_road_mundri_rumbek_062, supplier_road_rumbek_maper_107,
      supplier_road_rumbek_cueibet_063, supplier_road_cueibet_tonj_064, supplier_road_tonj_wau_065, supplier_road_wau_aweil_007, supplier_road_wau_deimzubier_130,
      supplier_road_deimzubier_raja_131, supplier_road_aweil_gokmachar_direct_009, supplier_road_aweil_gokmachar_ariath_044, supplier_road_aweil_wanyjok_010,
      supplier_road_kiiradem_gokmachar_012, supplier_road_meram_wanyjok_013, supplier_road_ameit_wanyjok_direct_014, supplier_road_gogrial_wanyjok_015,
      supplier_road_ameit_wunrok_019, supplier_road_wunrok_gogrial_137, supplier_road_gogrial_kuajok_136, supplier_road_wau_kuajok_016,
      supplier_road_ameit_abiemnhom_067, supplier_road_abiemnhom_mayom_068, supplier_road_mayom_rubkona_069, supplier_road_rubkona_bentiu_070,
      supplier_road_juba_mangalla_127, supplier_road_mangalla_gemmaiza_128, supplier_road_gemmaiza_bor_129, supplier_road_bor_pibor_028,
      supplier_road_bor_akobo_025, supplier_road_bor_panyagor_023, supplier_road_panyagor_puktap_047, supplier_road_puktap_dukpadiet_071,
      supplier_road_dukpadiet_yuai_072, supplier_road_dukpadiet_ayod_076, supplier_road_yuai_pieri_077, supplier_road_lankien_waat_073,
      supplier_road_dukpadiet_waat_126, supplier_road_waat_akobo_074, # supplier_road_dukpadiet_mwottot_046,
      supplier_road_pibor_akobo_026,
      supplier_road_narus_pochala_029, supplier_road_narus_boma_081, supplier_road_renk_paloich_030, supplier_road_paloich_maban_031, supplier_road_paloich_melut_032,
      supplier_road_paloich_malakal_034, supplier_road_mundri_maridi_084, supplier_road_yei_maridi_037, supplier_road_morobo_yei_038, supplier_road_yei_dimo_140,
      supplier_road_morobo_bazi_123, supplier_road_morobo_kaya_124, supplier_road_maridi_ibba_138, supplier_road_ibba_yambio_139, supplier_road_yambio_nabiapai_141,
      supplier_road_yambio_sakure_142, supplier_road_nzara_bagugu_143, supplier_road_diabio_ezo_144, supplier_road_tambura_sourceyubu_145,
      supplier_road_yambio_tambura_040, supplier_road_tambura_nagero_132, supplier_road_nagero_wau_133, supplier_road_juba_torit_041, supplier_road_torit_kapoeta_042,
      supplier_road_kapoeta_narus_117, supplier_road_malakal_lankien_052, supplier_road_malakal_baliet_085, supplier_road_baliet_ulang_086,
      supplier_road_ulang_nasir_051, supplier_road_juba_lafon_089, supplier_road_torit_lafon_090, supplier_road_torit_magwi_091, supplier_road_magwi_labone_083,
      supplier_road_magwi_ngomoromo_125, supplier_road_torit_ikotos_092, supplier_road_ikotos_trestenya_108, supplier_road_ikotos_bira_122,
      supplier_road_juba_magwi_120, supplier_road_juba_kajokeji_093, supplier_road_kajokeji_jale_121, supplier_road_juba_lainya_134, supplier_road_lainya_yei_135,
      supplier_road_yirol_shambe_095, supplier_road_pagak_maiwut_109, supplier_road_pagak_mathiang_097, supplier_road_mathiang_guel_098, supplier_road_guit_leer_099,
      supplier_road_mayendit_panyijiar_100, supplier_road_rubkona_pariang_101, supplier_road_pariang_yida_102, supplier_road_pariang_jamjang_110,
      supplier_road_pariang_pamir_111, supplier_road_pariang_ajuongthok_112, supplier_road_tishwin_rubkona_103, supplier_road_bentiu_koch_104,
      supplier_road_bentiu_guit_105, supplier_road_koch_leer_106, supplier_road_tallodi_tonga_116, supplier_river_juba_bor_022, supplier_river_tiek_nyal_043,
      supplier_river_taiyar_ganylel_118, supplier_river_renk_melut_033, supplier_river_melut_malakal_035, supplier_river_malakal_ulang_055, supplier_river_ulang_dome_119,
      supplier_river_ulang_nasir_056, supplier_river_jikou_akobo_053, supplier_river_jikou_nasir_054, supplier_river_juba_malakal_113,
      supplier_river_juba_newfangak_114, supplier_river_juba_bentiu_115, supplier_road_gumuruk_mangalla_150
    )


  # ============================================== SUPPLY MARKET ==========================================================

  # The mode function has issues dealing with blank values (it assumes they are data points and includes them in the calculation)
  # filter out the missing data points so that the mode function works properly

  supply_local_food <- jmmi %>%
    select(state, county, location, food_supplier_local_calc) %>%
    filter(food_supplier_local_calc != "")

  supply_import_food <- jmmi %>%
    select(state, county, location, food_supplier_imported_calc) %>%
    filter(food_supplier_imported_calc != "")


  supply_import_nfi <- jmmi %>%
    select(state, county, location, nfi_supplier_calc) %>%
    filter(nfi_supplier_calc != "")

  supply_1 <- full_join(supply_import_nfi, supply_import_food, by = c("state", "county", "location"))
  supply <- full_join(supply_1, supply_local_food, by = c("state", "county", "location"))



  # Apply the supply market aggregation function:

  # --------- 13

  supply <- supply %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), mode)) %>%
    select(state, county, location, food_supplier_local_calc, food_supplier_imported_calc, nfi_supplier_calc)


  # Filter out all relevant columns on supply markets (for "all_supply" tab in analysis worksheet):

  all_supply <- jmmi %>%
    select(
      state, county, location, marketplace, entry,
      # food_supplier_local_same,food_supplier_local_producer,food_supplier_local_calc,food_supplier_local_transport,
      # food_supplier_imported_same,food_supplier_imported_calc,food_supplier_imported_transport,
      # nfi_supplier_calc,nfi_supplier_transport
      contains("food_supplier_local") & -contains("modality"),
      contains("food_supplier_imported"),
      contains("nfi_supplier") & -contains("modality")
    )


  # ============================================== FEEDBACK ==========================================================


  # Filter out all relevant columns from the feedback form data:

  feedback.export <- feedback %>%
    select(state, county, location, sorghum_vs_maize, cereals_availability, three_months_traders, three_months_supplies, last_year_traders, last_year_supplies) %>%
    group_by(state, county, location)


  # Filter out all columns indicating the reasons for not submitting 4 quotations per item. This is used for the "quotation" tab in the analysis worksheet.

  feedback.quotation <- feedback %>%
    select(
      state, county, location, marketplace,
      less_than_4_quotations_sorghum_grain, less_than_4_quotations_maize_grain, less_than_4_quotations_wheat_flour, less_than_4_quotations_rice, less_than_4_quotations_groundnuts,
      less_than_4_quotations_beans, less_than_4_quotations_sugar, less_than_4_quotations_salt, less_than_4_quotations_cooking_oil, less_than_4_quotations_soap,
      less_than_4_quotations_jerrycan, less_than_4_quotations_mosquito_net, less_than_4_quotations_exercise_book, less_than_4_quotations_blanket, less_than_4_quotations_cooking_pot,
      less_than_4_quotations_plastic_sheet, less_than_4_quotations_pole, less_than_4_quotations_firewood, less_than_4_quotations_charcoal, # less_than_4_quotations_sleeping_mat,
      less_than_4_quotations_goat, less_than_4_quotations_chicken,
      less_than_2_quotations_milling_why, less_than_2_quotations_USD, less_than_2_quotations_SDG,
      less_than_2_quotations_ETB, less_than_2_quotations_UGX, less_than_2_quotations_KES, less_than_2_quotations_CDF, less_than_2_quotations_XAF
    ) %>%
    group_by(state, county, location, marketplace) %>%
    arrange(state, county, location, marketplace) # less_than_5_quotations_labor_why,

  # Run the aggregation function over the availability data from the feedback form:

  feedback.availability <- feedback %>%
    select(
      state, county, location,
      items_available_food_dry.sorghum_grain, items_available_food_dry.sorghum_flour, items_available_food_dry.maize_grain, items_available_food_dry.maize_flour,
      items_available_food_dry.wheat_flour, items_available_food_dry.cassava_flour, items_available_food_dry.rice, items_available_food_dry.millet, items_available_food_dry.groundnuts,
      items_available_food_dry.beans, items_available_food_dry.cowpea, items_available_food_dry.lentils, items_available_food_dry.sesame,
      items_available_food_dry.salt, items_available_food_dry.sugar, items_available_food_dry.cooking_oil, items_available_food_dry.milk_powder,
      items_available_food_dry.fish_dried,
      items_available_food_fresh.honey, items_available_food_fresh.potatoes, items_available_food_fresh.okra, items_available_food_fresh.onion,
      items_available_food_fresh.tomatoes, items_available_food_fresh.banana, items_available_food_fresh.mango, items_available_food_fresh.milk_fresh, items_available_food_fresh.fish_fresh, items_available_food_fresh.beef,
      items_available_nfi.soap, items_available_nfi.jerrycan, items_available_nfi.buckets, items_available_nfi.bleach, items_available_nfi.mosquito_net, items_available_nfi.sanitary_pads,
      items_available_nfi.exercise_book, items_available_nfi.pens, items_available_nfi.blanket, items_available_nfi.clothing, items_available_nfi.footwear, items_available_nfi.cooking_pot, items_available_nfi.cooking_utensils,
      items_available_nfi.plastic_sheet, items_available_nfi.iron_sheets, items_available_nfi.pole, items_available_nfi.solar_lamp, items_available_nfi.firewood, items_available_nfi.charcoal,
      items_available_nfi.petrol, items_available_nfi.diesel, items_available_nfi.medicine, items_available_nfi.phone_credit, items_available_nfi.sleeping_mat,
      items_available_livestock.bull, items_available_livestock.goat, items_available_livestock.sheep, items_available_livestock.chicken,
      items_available_nutrition.plumpy_nut, items_available_nutrition.plumpy_sup, items_available_nutrition.csb, items_available_nutrition.bp5,
      items_unavailable.sorghum_grain, items_unavailable.maize_grain, items_unavailable.wheat_flour, items_unavailable.rice, items_unavailable.groundnuts,
      items_unavailable.beans, items_unavailable.sugar, items_unavailable.salt, items_unavailable.cooking_oil, items_unavailable.soap, items_unavailable.jerrycan,
      items_unavailable.mosquito_net, items_unavailable.exercise_book, items_unavailable.blanket, items_unavailable.cooking_pot, items_unavailable.plastic_sheet,
      items_unavailable.pole, items_unavailable.firewood, items_unavailable.charcoal, items_unavailable.goat, items_unavailable.chicken, items_unavailable.SSP,
      items_unavailable.USD, items_unavailable.SDG, items_unavailable.ETB, items_unavailable.UGX, items_unavailable.KES, items_unavailable.CDF,
      items_unavailable.XAF, items_unavailable.sleeping_mat
    ) %>%
    group_by(state, county, location) %>%
    arrange(state, county, location) %>%
    summarise(across(everything(), feedback.availability))

  # ============================================== Other Indicators =======================================================

  restock_constraints <- jmmi %>%
    select(starts_with("restock_constraints.")) %>%
    filter(!is.na(restock_constraints.none)) %>%
    rename(
      "No Constraints" = restock_constraints.none, "Checkpoint costs" = restock_constraints.checkpoints,
      "Border closures" = restock_constraints.border_closed, "Bad road conditions" = restock_constraints.road_conditions,
      "High taxation" = restock_constraints.high_taxation, "Insecurity along the supply route" = restock_constraints.insecurity_route,
      "Lack of foreign currency" = restock_constraints.no_foreign_currency, "No capital" = restock_constraints.no_capital,
      "Lack of supplies" = restock_constraints.no_supplies, "Bad river conditions" = restock_constraints.river_conditions,
      "No mode of transport" = restock_constraints.no_transport, "Lack of storage" = restock_constraints.no_storage,
      "Insecurity in the marketplace" = restock_constraints.insecurity_marketplace, "Other" = restock_constraints.other,
      "Price of fuel" = restock_constraints.fuel, "Don't know" = restock_constraints.dont_know
    )

  # create matrix

  restock_names <- names(restock_constraints)
  col_num <- length(restock_constraints)
  restock_constraint_matrix <- matrix(nrow = 1, ncol = ncol(restock_constraints))
  colnames(restock_constraint_matrix) <- restock_names

  for (ind in 1:col_num) {
    tmp <- restock_constraints[, ind]
    if ("1" %in% tmp | "0" %in% tmp) {
      tmp_count_yes <- sum(tmp %in% "1")
      tmp_prop_yes_2 <- (tmp_count_yes / nrow(restock_constraints))
      restock_constraint_matrix[1, ind] <- tmp_prop_yes_2
    } else {
      restock_constraint_matrix[1, ind] <- NA
    }
  }

  # Sort from ascending to descending order
  restock_constraint_matrix <- restock_constraint_matrix[, order(restock_constraint_matrix[1, ], decreasing = T)]
  restock_constraints_df <- as.data.frame(restock_constraint_matrix)

  # Add sections related to the chartwell bars

  restock_constraints_df_2 <- restock_constraints_df %>%
    mutate(percent = (round(restock_constraint_matrix, digits = 2) * 100)) %>%
    mutate(cw_1 = percent * 5) %>%
    mutate(cw_2 = 500 - cw_1) %>%
    select(-restock_constraint_matrix)

  # Add rows for names

  row.names(restock_constraints_df_2) <- rownames(restock_constraints_df)

  # Payment Modalities

  # restock constraints

  payment_modalities <- jmmi %>%
    select(starts_with("modalities_which.")) %>%
    filter(!is.na(modalities_which.cash_ssp)) %>%
    rename(
      "SSP" = modalities_which.cash_ssp, "USD" = modalities_which.cash_usd, "Other Cash" = modalities_which.cash_other, "Mobile Money" = modalities_which.mobile_money,
      "Credit" = modalities_which.credit, "Barter" = modalities_which.barter, "Other" = modalities_which.other, "Don't know" = modalities_which.dont_know
    )

  # create matrix

  modalities_names <- names(payment_modalities)
  col_num <- length(payment_modalities)
  payment_modalities_matrix <- matrix(nrow = 1, ncol = ncol(payment_modalities))
  colnames(payment_modalities_matrix) <- modalities_names


  for (ind in 1:col_num) {
    tmp <- payment_modalities[, ind]
    if ("1" %in% tmp | "0" %in% tmp) {
      tmp_count_yes <- sum(tmp %in% "1")
      tmp_prop_yes_2 <- (tmp_count_yes / nrow(payment_modalities))
      payment_modalities_matrix[1, ind] <- tmp_prop_yes_2
    } else {
      payment_modalities_matrix[1, ind] <- NA
    }
  }

  # Sort from ascending to descending order
  payment_modalities_matrix <- payment_modalities_matrix[, order(payment_modalities_matrix[1, ], decreasing = T)]
  payment_modalities_df <- as.data.frame(payment_modalities_matrix)

  # Add sections related to the chartwell bars

  payment_modalities_df_2 <- payment_modalities_df %>%
    mutate(percent = (round(payment_modalities_matrix, digits = 2) * 100)) %>%
    mutate(cw_1 = percent * 5) %>%
    mutate(cw_2 = 500 - cw_1) %>%
    select(-payment_modalities_matrix)

  # Add rows for names

  row.names(payment_modalities_df_2) <- rownames(payment_modalities_df)

  # Medium of transport for locally supplied goods

  transport_matrix <- matrix(nrow = 11, ncol = 2)
  colnames(transport_matrix) <- c("transport", "frequency")
  rownames(transport_matrix) <- c("airplane", "bicycle", "boat", "boda", "canoe", "car", "people", "ship", "tractor", "truck", "other")
  transport_matrix[1, 1] <- sum(jmmi$food_supplier_local_transport %in% "airplane", na.rm = TRUE)
  transport_matrix[2, 1] <- sum(jmmi$food_supplier_local_transport %in% "bicycle", na.rm = TRUE)
  transport_matrix[3, 1] <- sum(jmmi$food_supplier_local_transport %in% "boat", na.rm = TRUE)
  transport_matrix[4, 1] <- sum(jmmi$food_supplier_local_transport %in% "boda", na.rm = TRUE)
  transport_matrix[5, 1] <- sum(jmmi$food_supplier_local_transport %in% "canoe", na.rm = TRUE)
  transport_matrix[6, 1] <- sum(jmmi$food_supplier_local_transport %in% "car", na.rm = TRUE)
  transport_matrix[7, 1] <- sum(jmmi$food_supplier_local_transport %in% "people", na.rm = TRUE)
  transport_matrix[8, 1] <- sum(jmmi$food_supplier_local_transport %in% "ship", na.rm = TRUE)
  transport_matrix[9, 1] <- sum(jmmi$food_supplier_local_transport %in% "tractor", na.rm = TRUE)
  transport_matrix[10, 1] <- sum(jmmi$food_supplier_local_transport %in% "truck", na.rm = TRUE)
  transport_matrix[11, 1] <- sum(jmmi$food_supplier_local_transport %in% "other", na.rm = TRUE)
  transport_matrix[, 2] <- round((transport_matrix[, 1] / sum(transport_matrix[, 1], na.rm = TRUE) * 100))
  transport_matrix <- transport_matrix[order(transport_matrix[, 2], decreasing = TRUE), ]

  # Price expectations

  # Cereals
  food_matrix <- matrix(nrow = 4, ncol = 2)
  colnames(food_matrix) <- c("cereal price expectations", "frequency")
  rownames(food_matrix) <- c("increase", "decrease", "no change", "don't know")
  food_matrix[1, 1] <- sum(jmmi$food_expectation_price_3months %in% "increase", na.rm = TRUE)
  food_matrix[2, 1] <- sum(jmmi$food_expectation_price_3months %in% "decrease", na.rm = TRUE)
  food_matrix[3, 1] <- sum(jmmi$food_expectation_price_3months %in% "no_change", na.rm = TRUE)
  food_matrix[4, 1] <- sum(jmmi$food_expectation_price_3months %in% "dont_know", na.rm = TRUE)
  food_matrix[, 2] <- round((food_matrix[, 1] / sum(food_matrix[, 1], na.rm = TRUE) * 100))

  # NFIs
  nfi_matrix <- matrix(nrow = 4, ncol = 2)
  colnames(nfi_matrix) <- c("NFI price expectations", "frequency")
  nfi_matrix[1, 1] <- sum(jmmi$nfi_expectation_price_3months %in% "increase", na.rm = TRUE)
  nfi_matrix[2, 1] <- sum(jmmi$nfi_expectation_price_3months %in% "decrease", na.rm = TRUE)
  nfi_matrix[3, 1] <- sum(jmmi$nfi_expectation_price_3months %in% "no_change", na.rm = TRUE)
  nfi_matrix[4, 1] <- sum(jmmi$nfi_expectation_price_3months %in% "dont_know", na.rm = TRUE)
  nfi_matrix[, 2] <- round((nfi_matrix[, 1] / sum(nfi_matrix[, 1], na.rm = TRUE) * 100))

  price_expectations <- cbind(food_matrix, nfi_matrix)

  # The next code calculates which denominations of SSP are accepted by traders who use the modality

  modalities_ssp <- jmmi %>%
    select(state, county, location, starts_with("modalities_ssp.")) %>%
    filter(!is.na(modalities_ssp.1)) %>%
    gather(key = Denomination, value = Use, modalities_ssp.1:modalities_ssp.500) %>%
    group_by(state, county, location, Denomination) %>%
    summarise_all(length) %>% # This is to find the total that were asked the question
    mutate(Denomination = gsub("modalities_ssp.", "", Denomination))

  modalities_ssp_2 <- jmmi %>%
    select(state, county, location, starts_with("modalities_ssp.")) %>%
    filter(!is.na(modalities_ssp.1)) %>%
    gather(key = Denomination, value = Freq, modalities_ssp.1:modalities_ssp.500) %>%
    group_by(state, county, location, Denomination) %>%
    summarise_all(sum) %>% # This is to take the sum of all mentioned that they accept a certain denomination for payment
    mutate(Denomination = gsub("modalities_ssp.", "", Denomination))

  ssp_denominations <- left_join(modalities_ssp, modalities_ssp_2)
  ssp_denominations <- ssp_denominations %>%
    group_by(state, county, location) %>%
    mutate(Denomination = as.numeric(Denomination)) %>%
    mutate(perc = (Freq / Use) * 100) %>% # This is the pecentage of traders per location accepting a certain denomination
    arrange(location, Denomination)


  # The next code calculates why traders (who don't accept mobile )

  no_mobile_money <- jmmi %>%
    select(starts_with("modalities_mobile_money.")) %>%
    filter(!is.na(modalities_mobile_money.no_phones)) %>%
    gather(key = Reason, value = length, modalities_mobile_money.no_phones:modalities_mobile_money.dont_know) %>%
    group_by(Reason) %>%
    summarise_all(length) # To find the total of people who were asked the question

  no_mobile_money_2 <- jmmi %>%
    select(starts_with("modalities_mobile_money.")) %>%
    filter(!is.na(modalities_mobile_money.no_phones)) %>%
    gather(key = Reason, value = sum, modalities_mobile_money.no_phones:modalities_mobile_money.dont_know) %>%
    group_by(Reason) %>%
    summarise_all(sum) # To find the amount of people who responded with a certain constraint

  mobile_money_reason <- left_join(no_mobile_money, no_mobile_money_2)
  mobile_money_reason <- mobile_money_reason %>%
    mutate(
      Reason = gsub("modalities_mobile_money.customer_id", "Customers do not have paperwork to acccess mobile money", Reason),
      Reason = gsub("modalities_mobile_money.documentation", "Too much required documentation for traders", Reason),
      Reason = gsub("modalities_mobile_money.dont_know", "Don't know", Reason),
      Reason = gsub("modalities_mobile_money.dont_know_how", "Don't know how to join", Reason),
      Reason = gsub("modalities_mobile_money.no_agent", "No available cash agent", Reason),
      Reason = gsub("modalities_mobile_money.no_network", "No mobile network in this area", Reason),
      Reason = gsub("modalities_mobile_money.no_phones", "Customers do not have phones", Reason),
      Reason = gsub("modalities_mobile_money.other", "Other", Reason),
      Reason = gsub("modalities_mobile_money.too_expensive_running", "Too expensive to run", Reason),
      Reason = gsub("modalities_mobile_money.too_expensive_setup", "Too expensive to set up", Reason)
    ) %>%
    mutate(perc = (sum / length) * 100) # percentage of trader (who does not use mobile money) reporting whatever reason


  # What do traders use to buy their locally supplied goods

  locally_supplied_food <- jmmi %>%
    select(state, county, location, food_supplier_local_sell, starts_with("food_supplier_local_modality.")) %>%
    filter(food_supplier_local_sell %in% "yes") %>%
    select(-food_supplier_local_sell) %>%
    gather(key = modality, value = Length, food_supplier_local_modality.cash_ssp:food_supplier_local_modality.dont_know) %>%
    group_by(state, county, location, modality) %>%
    summarise_all(length) # To find the total of people who were asked the question

  locally_supplied_food_2 <- jmmi %>%
    select(state, county, location, food_supplier_local_sell, starts_with("food_supplier_local_modality.")) %>%
    filter(food_supplier_local_sell %in% "yes") %>%
    select(-food_supplier_local_sell) %>%
    gather(key = modality, value = Sum, food_supplier_local_modality.cash_ssp:food_supplier_local_modality.dont_know) %>%
    group_by(state, county, location, modality) %>%
    summarise_all(sum) # To find the amount of people who responded with a certain constraint

  locally_supplied_trade <- left_join(locally_supplied_food, locally_supplied_food_2)
  locally_supplied_trade <- locally_supplied_trade %>%
    mutate(
      modality = gsub("food_supplier_local_modality.barter", "Bartering", modality),
      modality = gsub("food_supplier_local_modality.cash_other", "Other Currency", modality),
      modality = gsub("food_supplier_local_modality.cash_ssp", "SSP", modality),
      modality = gsub("food_supplier_local_modality.cash_usd", "USD", modality),
      modality = gsub("food_supplier_local_modality.credit", "Credit", modality),
      modality = gsub("food_supplier_local_modality.dont_know", "Don't Know", modality),
      modality = gsub("food_supplier_local_modality.mobile_money", "Mobile Money", modality),
      modality = gsub("food_supplier_local_modality.other", "Other", modality)
    ) %>%
    group_by(state, county, location) %>%
    mutate(perc = (Sum / Length) * 100) # percentage of trader aggregated to location level using what modality to buy local sorghum or cereals


  # What do traders use to buy locally imported food goods

  locally_imported_food <- jmmi %>%
    select(state, county, location, food_supplier_imported_sell, starts_with("food_supplier_modality.")) %>%
    filter(food_supplier_imported_sell %in% "yes") %>%
    select(-food_supplier_imported_sell) %>%
    gather(key = modality, value = Length, food_supplier_modality.cash_ssp:food_supplier_modality.dont_know) %>%
    group_by(state, county, location, modality) %>%
    summarise_all(length) # To find the total of people who were asked the question

  locally_imported_food_2 <- jmmi %>%
    select(state, county, location, food_supplier_imported_sell, starts_with("food_supplier_modality.")) %>%
    filter(food_supplier_imported_sell %in% "yes") %>%
    select(-food_supplier_imported_sell) %>%
    gather(key = modality, value = Sum, food_supplier_modality.cash_ssp:food_supplier_modality.dont_know) %>%
    group_by(state, county, location, modality) %>%
    summarise_all(sum) # To find the amount of people who responded with a certain constraint

  imported_food_trade <- left_join(locally_imported_food, locally_imported_food_2)
  imported_food_trade <- imported_food_trade %>%
    group_by(state, county, location) %>%
    mutate(perc = (Sum / Length) * 100) # percentage of trader aggregated to location level using what modality to buy imported food gods


  # What do traders use to buy locally imported food goods

  nfi_imported <- jmmi %>%
    select(state, county, location, starts_with("nfi_supplier_modality.")) %>%
    filter(!is.na(nfi_supplier_modality.cash_ssp)) %>%
    gather(key = modality, value = Length, nfi_supplier_modality.cash_ssp:nfi_supplier_modality.dont_know) %>%
    group_by(state, county, location, modality) %>%
    summarise_all(length) # To find the total of people who were asked the question

  nfi_imported_2 <- jmmi %>%
    select(state, county, location, starts_with("nfi_supplier_modality.")) %>%
    filter(!is.na(nfi_supplier_modality.cash_ssp)) %>%
    gather(key = modality, value = Sum, nfi_supplier_modality.cash_ssp:nfi_supplier_modality.dont_know) %>%
    group_by(state, county, location, modality) %>%
    summarise(across(everything(), ~ sum(., na.rm = TRUE))) # To find the amount of people who responded with a certain constraint

  nfi_trade <- left_join(nfi_imported, nfi_imported_2)
  nfi_trade <- nfi_trade %>%
    mutate(
      modality = gsub("nfi_supplier_modality.barter", "Bartering", modality),
      modality = gsub("nfi_supplier_modality.cash_other", "Other Currency", modality),
      modality = gsub("nfi_supplier_modality.cash_ssp", "SSP", modality),
      modality = gsub("nfi_supplier_modality.cash_usd", "USD", modality),
      modality = gsub("nfi_supplier_modality.credit", "Credit", modality),
      modality = gsub("nfi_supplier_modality.dont_know", "Don't Know", modality),
      modality = gsub("nfi_supplier_modality.mobile_money", "Mobile Money", modality),
      modality = gsub("nfi_supplier_modality.other", "Other", modality)
    ) %>%
    group_by(state, county, location) %>%
    mutate(perc = (Sum / Length) * 100) # percentage of trader aggregated to location level using what modality to buy imported NFIs



  # ============================================== Insecurity present within marketplace ==================================
  # this is used to note if there is any insecurity which will be used to inform the MFI

  insecurity_marketplace <- jmmi %>%
    select(state, county, location, restock_constraints.insecurity_marketplace) %>%
    group_by(state, county, location) %>%
    summarise(across(everything(), sum)) %>%
    mutate("Security issues in Markeplace" = ifelse(restock_constraints.insecurity_marketplace > 1, "!", ""))


  # ============================================== CHANGES (loc) ==========================================================


  # In this section, the changes over time are calculated.
  # First, we adjust the data we imported from the median tab in the ANALYSIS WORKSHEET. Delete all the rows that we don't need, and only keep the columns with indices.


  median.indices <- median.indices %>%
    filter(State != "") %>%
    select("Food.price.index", "MSSMEB.food.basket", "MSSMEB")
  # Secondly, add the indices to the median2 dataframe.

  median.chg <- bind_cols(median, median.indices) %>%
    mutate(
      MSSMEB.USD = MSSMEB / USD,
      MSSMEB.food.basket.USD = MSSMEB.food.basket / USD,
      Month = month_curr,
      Year = year_curr
    ) %>%
    select(Year, Month, everything()) %>%
    mutate(across(everything() & -contains(c("State", "County", "Location")), as.numeric))

  # Delete current month's data from longterm dataset:
  longterm <- longterm %>% filter(!(Month == month_curr & Year == year_curr))

  # Join the data from the latest month with the longterm dataset to create an updated longterm dataframe:
  median.chg <- full_join(longterm, median.chg)

  # Filter out the months for which you want to calculate the changes (this is important to make sure the below aggregation function works correctly):
  median.chg.1m <- median.chg %>% filter(Month == month_prev & Year == year_prev | Month == month_curr & Year == year_curr)

  median.chg.1m <- median.chg.1m %>%
    group_by(State, County, Location) %>%
    arrange(Year, Month) %>%
    mutate(
      Sorghum.grain.chg = Sorghum.grain / lag(Sorghum.grain) - 1,
      Maize.grain.chg = Maize.grain / lag(Maize.grain) - 1,
      Wheat.flour.chg = Wheat.flour / lag(Wheat.flour) - 1,
      Rice.chg = Rice / lag(Rice) - 1,
      Groundnuts.chg = Groundnuts / lag(Groundnuts) - 1,
      Beans.chg = Beans / lag(Beans) - 1,
      Sugar.chg = Sugar / lag(Sugar) - 1,
      Salt.chg = Salt / lag(Salt) - 1,
      Cooking.oil.chg = Cooking.oil / lag(Cooking.oil) - 1,
      Soap.chg = Soap / lag(Soap) - 1,
      Jerrycan.chg = Jerrycan / lag(Jerrycan) - 1,
      Mosquito.net.chg = Mosquito.net / lag(Mosquito.net) - 1,
      Exercise.book.chg = Exercise.book / lag(Exercise.book) - 1,
      Blanket.chg = Blanket / lag(Blanket) - 1,
      Cooking.pot.chg = Cooking.pot / lag(Cooking.pot) - 1,
      Plastic.sheet.chg = Plastic.sheet / lag(Plastic.sheet) - 1,
      Pole.chg = Pole / lag(Pole) - 1,
      Firewood.chg = Firewood / lag(Firewood) - 1,
      Charcoal.chg = Charcoal / lag(Charcoal) - 1,
      Goat.chg = Goat / lag(Goat) - 1,
      Chicken.chg = Chicken / lag(Chicken) - 1,
      Milling.costs.chg = Milling.costs / lag(Milling.costs) - 1,
      Rubber.rope.chg = Rubber.rope / lag(Rubber.rope) - 1,
      Kanga.chg = Kanga / lag(Kanga) - 1,
      Solar.lamp.chg = Solar.lamp / lag(Solar.lamp) - 1,
      # Aqua.tab.chg = Aqua.tab/lag(Aqua.tab)-1,
      Plastic.bucket.chg = Plastic.bucket / lag(Plastic.bucket) - 1,
      Sanitary.pad.chg = Sanitary.pad / lag(Sanitary.pad) - 1,
      Pen.chg = Pen / lag(Pen) - 1,
      Pencil.chg = Pencil / lag(Pencil) - 1,
      Rubber.chg = Rubber / lag(Rubber) - 1,
      Sharpener.chg = Sharpener / lag(Sharpener) - 1,
      Sleeping.mat.chg = Sleeping.mat / lag(Sleeping.mat) - 1,
      Bamboo.chg = Bamboo / lag(Bamboo) - 1,
      Underwear.chg = Underwear / lag(Underwear) - 1,
      School.bag.chg = School.bag / lag(School.bag) - 1,
      Bra.chg = Bra / lag(Bra) - 1,
      Grass.chg = Grass / lag(Grass) - 1,
      USD.chg = USD / lag(USD) - 1,
      SDG.chg = SDG / lag(SDG) - 1,
      ETB.chg = ETB / lag(ETB) - 1,
      UGX.chg = UGX / lag(UGX) - 1,
      KES.chg = KES / lag(KES) - 1,
      CDF.chg = CDF / lag(CDF) - 1,
      XAF.chg = XAF / lag(XAF) - 1,
      Food.price.index.chg = Food.price.index / lag(Food.price.index) - 1,
      MSSMEB.food.basket.chg = MSSMEB.food.basket / lag(MSSMEB.food.basket) - 1,
      MSSMEB.chg = MSSMEB / lag(MSSMEB) - 1,
      MSSMEB.food.basket.chg.USD = MSSMEB.food.basket.USD / lag(MSSMEB.food.basket.USD) - 1,
      MSSMEB.chg.USD = MSSMEB.USD / lag(MSSMEB.USD) - 1
    ) %>%
    select(Year, Month, State, County, Location, contains(".chg")) %>%
    filter(Month == month_curr & Year == year_curr) %>% # Delete all changes that are not for the most recent month. Then, delete the month and year columns:
    select(-c(Month, Year))


  median.chg.3m <- median.chg %>% filter(Month == month_lag_3 & Year == year_lag_3 | Month == month_curr & Year == year_curr)

  median.chg.3m <- median.chg.3m %>%
    group_by(State, County, Location) %>%
    arrange(Year, Month) %>%
    mutate(
      Sorghum.grain.chg = Sorghum.grain / lag(Sorghum.grain) - 1,
      Maize.grain.chg = Maize.grain / lag(Maize.grain) - 1,
      Wheat.flour.chg = Wheat.flour / lag(Wheat.flour) - 1,
      Rice.chg = Rice / lag(Rice) - 1,
      Groundnuts.chg = Groundnuts / lag(Groundnuts) - 1,
      Beans.chg = Beans / lag(Beans) - 1,
      Sugar.chg = Sugar / lag(Sugar) - 1,
      Salt.chg = Salt / lag(Salt) - 1,
      Cooking.oil.chg = Cooking.oil / lag(Cooking.oil) - 1,
      Soap.chg = Soap / lag(Soap) - 1,
      Jerrycan.chg = Jerrycan / lag(Jerrycan) - 1,
      Mosquito.net.chg = Mosquito.net / lag(Mosquito.net) - 1,
      Exercise.book.chg = Exercise.book / lag(Exercise.book) - 1,
      Blanket.chg = Blanket / lag(Blanket) - 1,
      Cooking.pot.chg = Cooking.pot / lag(Cooking.pot) - 1,
      Plastic.sheet.chg = Plastic.sheet / lag(Plastic.sheet) - 1,
      Pole.chg = Pole / lag(Pole) - 1,
      Firewood.chg = Firewood / lag(Firewood) - 1,
      Charcoal.chg = Charcoal / lag(Charcoal) - 1,
      Goat.chg = Goat / lag(Goat) - 1,
      Chicken.chg = Chicken / lag(Chicken) - 1,
      Milling.costs.chg = Milling.costs / lag(Milling.costs) - 1,
      Rubber.rope.chg = Rubber.rope / lag(Rubber.rope) - 1,
      Kanga.chg = Kanga / lag(Kanga) - 1,
      Solar.lamp.chg = Solar.lamp / lag(Solar.lamp) - 1,
      # Aqua.tab.chg = Aqua.tab/lag(Aqua.tab)-1,
      Plastic.bucket.chg = Plastic.bucket / lag(Plastic.bucket) - 1,
      Sanitary.pad.chg = Sanitary.pad / lag(Sanitary.pad) - 1,
      Pen.chg = Pen / lag(Pen) - 1,
      Pencil.chg = Pencil / lag(Pencil) - 1,
      Rubber.chg = Rubber / lag(Rubber) - 1,
      Sharpener.chg = Sharpener / lag(Sharpener) - 1,
      Sleeping.mat.chg = Sleeping.mat / lag(Sleeping.mat) - 1,
      Bamboo.chg = Bamboo / lag(Bamboo) - 1,
      Underwear.chg = Underwear / lag(Underwear) - 1,
      School.bag.chg = School.bag / lag(School.bag) - 1,
      Bra.chg = Bra / lag(Bra) - 1,
      Grass.chg = Grass / lag(Grass) - 1,
      USD.chg = USD / lag(USD) - 1,
      SDG.chg = SDG / lag(SDG) - 1,
      ETB.chg = ETB / lag(ETB) - 1,
      UGX.chg = UGX / lag(UGX) - 1,
      KES.chg = KES / lag(KES) - 1,
      CDF.chg = CDF / lag(CDF) - 1,
      XAF.chg = XAF / lag(XAF) - 1,
      Food.price.index.chg = Food.price.index / lag(Food.price.index) - 1,
      MSSMEB.food.basket.chg = MSSMEB.food.basket / lag(MSSMEB.food.basket) - 1,
      MSSMEB.chg = MSSMEB / lag(MSSMEB) - 1,
      MSSMEB.food.basket.chg.USD = MSSMEB.food.basket.USD / lag(MSSMEB.food.basket.USD) - 1,
      MSSMEB.chg.USD = MSSMEB.USD / lag(MSSMEB.USD) - 1
    ) %>%
    select(Year, Month, State, County, Location, contains(".chg")) %>%
    filter(Month == month_curr & Year == year_curr) %>% # Delete all changes that are not for the most recent month. Then, delete the month and year columns:
    select(-c(Month, Year))


  # Filter out the months for which you want to calculate the longterm changes (this is important to make sure the below aggregation function works correctly):

  median.chg.long <- median.chg %>% filter(Month == month_long & Year == year_long | Month == month_curr & Year == year_curr)


  median.chg.long <- median.chg.long %>%
    group_by(State, County, Location) %>%
    arrange(Year, Month) %>%
    mutate(
      Sorghum.grain.chg = Sorghum.grain / lag(Sorghum.grain) - 1,
      Maize.grain.chg = Maize.grain / lag(Maize.grain) - 1,
      Wheat.flour.chg = Wheat.flour / lag(Wheat.flour) - 1,
      Rice.chg = Rice / lag(Rice) - 1,
      Groundnuts.chg = Groundnuts / lag(Groundnuts) - 1,
      Beans.chg = Beans / lag(Beans) - 1,
      Sugar.chg = Sugar / lag(Sugar) - 1,
      Salt.chg = Salt / lag(Salt) - 1,
      Cooking.oil.chg = Cooking.oil / lag(Cooking.oil) - 1,
      Soap.chg = Soap / lag(Soap) - 1,
      Jerrycan.chg = Jerrycan / lag(Jerrycan) - 1,
      Mosquito.net.chg = Mosquito.net / lag(Mosquito.net) - 1,
      Exercise.book.chg = Exercise.book / lag(Exercise.book) - 1,
      Blanket.chg = Blanket / lag(Blanket) - 1,
      Cooking.pot.chg = Cooking.pot / lag(Cooking.pot) - 1,
      Plastic.sheet.chg = Plastic.sheet / lag(Plastic.sheet) - 1,
      Pole.chg = Pole / lag(Pole) - 1,
      Firewood.chg = Firewood / lag(Firewood) - 1,
      Charcoal.chg = Charcoal / lag(Charcoal) - 1,
      Goat.chg = Goat / lag(Goat) - 1,
      Chicken.chg = Chicken / lag(Chicken) - 1,
      Milling.costs.chg = Milling.costs / lag(Milling.costs) - 1,
      Rubber.rope.chg = Rubber.rope / lag(Rubber.rope) - 1,
      Kanga.chg = Kanga / lag(Kanga) - 1,
      Solar.lamp.chg = Solar.lamp / lag(Solar.lamp) - 1,
      # Aqua.tab.chg = Aqua.tab/lag(Aqua.tab)-1,
      Plastic.bucket.chg = Plastic.bucket / lag(Plastic.bucket) - 1,
      Sanitary.pad.chg = Sanitary.pad / lag(Sanitary.pad) - 1,
      Pen.chg = Pen / lag(Pen) - 1,
      Pencil.chg = Pencil / lag(Pencil) - 1,
      Rubber.chg = Rubber / lag(Rubber) - 1,
      Sharpener.chg = Sharpener / lag(Sharpener) - 1,
      Sleeping.mat.chg = Sleeping.mat / lag(Sleeping.mat) - 1,
      Bamboo.chg = Bamboo / lag(Bamboo) - 1,
      Underwear.chg = Underwear / lag(Underwear) - 1,
      School.bag.chg = School.bag / lag(School.bag) - 1,
      Bra.chg = Bra / lag(Bra) - 1,
      Grass.chg = Grass / lag(Grass) - 1,
      USD.chg = USD / lag(USD) - 1,
      SDG.chg = SDG / lag(SDG) - 1,
      ETB.chg = ETB / lag(ETB) - 1,
      UGX.chg = UGX / lag(UGX) - 1,
      KES.chg = KES / lag(KES) - 1,
      CDF.chg = CDF / lag(CDF) - 1,
      XAF.chg = XAF / lag(XAF) - 1,
      Food.price.index.chg = Food.price.index / lag(Food.price.index) - 1,
      MSSMEB.food.basket.chg = MSSMEB.food.basket / lag(MSSMEB.food.basket) - 1,
      MSSMEB.chg = MSSMEB / lag(MSSMEB) - 1,
      MSSMEB.food.basket.chg.USD = MSSMEB.food.basket.USD / lag(MSSMEB.food.basket.USD) - 1,
      MSSMEB.chg.USD = MSSMEB.USD / lag(MSSMEB.USD) - 1
    ) %>%
    select(Year, Month, State, County, Location, contains(".chg")) %>%
    filter(Month == month_curr & Year == year_curr) %>% # Delete all changes that are not for the most recent month. Then, delete the month and year columns:
    select(-c(Month, Year))



  # ============================================== CHANGES (overall) ==========================================================


  # Run the median aggregation function to get the overall medians per item and month:

  median.chg.overall <- median.chg %>%
    select(
      "Year", "Month", "Sorghum.grain", "Maize.grain", "Wheat.flour", "Rice", "Groundnuts", "Beans", "Sugar", "Salt", "Cooking.oil", "Soap", "Jerrycan", "Mosquito.net", "Exercise.book",
      "Blanket", "Cooking.pot", "Plastic.sheet", "Pole", "Firewood", "Charcoal", "Goat", "Chicken", "Milling.costs", "USD", "SDG", "ETB", "UGX", "KES",
      "CDF", "XAF", "Food.price.index", "MSSMEB.food.basket", "MSSMEB", "MSSMEB.food.basket.USD", "MSSMEB.USD",
      "Rubber.rope", "Kanga", "Solar.lamp", # "Aqua.tab",
      "Plastic.bucket", "Sanitary.pad", "Pen", "Pencil", "Rubber", "Sharpener", "Sleeping.mat", "Bamboo", "Grass", "Underwear", "School.bag", "Bra"
    ) %>%
    group_by(Year, Month) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))


  # Filter out the months for which you want to calculate the monthly changes (this is important to make sure the below aggregation function works correctly):

  median.chg.overall.1m <- median.chg.overall %>% filter(Month == month_prev & Year == year_prev | Month == month_curr & Year == year_curr)

  median.chg.overall.1m <- median.chg.overall.1m %>%
    ungroup() %>%
    arrange(Year, Month) %>%
    mutate(
      Sorghum.grain.chg = Sorghum.grain / lag(Sorghum.grain) - 1,
      Maize.grain.chg = Maize.grain / lag(Maize.grain) - 1,
      Wheat.flour.chg = Wheat.flour / lag(Wheat.flour) - 1,
      Rice.chg = Rice / lag(Rice) - 1,
      Groundnuts.chg = Groundnuts / lag(Groundnuts) - 1,
      Beans.chg = Beans / lag(Beans) - 1,
      Sugar.chg = Sugar / lag(Sugar) - 1,
      Salt.chg = Salt / lag(Salt) - 1,
      Cooking.oil.chg = Cooking.oil / lag(Cooking.oil) - 1,
      Soap.chg = Soap / lag(Soap) - 1,
      Jerrycan.chg = Jerrycan / lag(Jerrycan) - 1,
      Mosquito.net.chg = Mosquito.net / lag(Mosquito.net) - 1,
      Exercise.book.chg = Exercise.book / lag(Exercise.book) - 1,
      Blanket.chg = Blanket / lag(Blanket) - 1,
      Cooking.pot.chg = Cooking.pot / lag(Cooking.pot) - 1,
      Plastic.sheet.chg = Plastic.sheet / lag(Plastic.sheet) - 1,
      Pole.chg = Pole / lag(Pole) - 1,
      Firewood.chg = Firewood / lag(Firewood) - 1,
      Charcoal.chg = Charcoal / lag(Charcoal) - 1,
      Goat.chg = Goat / lag(Goat) - 1,
      Chicken.chg = Chicken / lag(Chicken) - 1,
      Milling.costs.chg = Milling.costs / lag(Milling.costs) - 1,
      Rubber.rope.chg = Rubber.rope / lag(Rubber.rope) - 1,
      Kanga.chg = Kanga / lag(Kanga) - 1,
      Solar.lamp.chg = Solar.lamp / lag(Solar.lamp) - 1,
      # Aqua.tab.chg = Aqua.tab/lag(Aqua.tab)-1,
      Plastic.bucket.chg = Plastic.bucket / lag(Plastic.bucket) - 1,
      Sanitary.pad.chg = Sanitary.pad / lag(Sanitary.pad) - 1,
      Pen.chg = Pen / lag(Pen) - 1,
      Pencil.chg = Pencil / lag(Pencil) - 1,
      Rubber.chg = Rubber / lag(Rubber) - 1,
      Sharpener.chg = Sharpener / lag(Sharpener) - 1,
      Sleeping.mat.chg = Sleeping.mat / lag(Sleeping.mat) - 1,
      Bamboo.chg = Bamboo / lag(Bamboo) - 1,
      Underwear.chg = Underwear / lag(Underwear) - 1,
      School.bag.chg = School.bag / lag(School.bag) - 1,
      Bra.chg = Bra / lag(Bra) - 1,
      Grass.chg = Grass / lag(Grass) - 1,
      USD.chg = USD / lag(USD) - 1,
      SDG.chg = SDG / lag(SDG) - 1,
      ETB.chg = ETB / lag(ETB) - 1,
      UGX.chg = UGX / lag(UGX) - 1,
      KES.chg = KES / lag(KES) - 1,
      CDF.chg = CDF / lag(CDF) - 1,
      XAF.chg = XAF / lag(XAF) - 1,
      Food.price.index.chg = Food.price.index / lag(Food.price.index) - 1,
      MSSMEB.food.basket.chg = MSSMEB.food.basket / lag(MSSMEB.food.basket) - 1,
      MSSMEB.chg = MSSMEB / lag(MSSMEB) - 1,
      MSSMEB.food.basket.chg.USD = MSSMEB.food.basket.USD / lag(MSSMEB.food.basket.USD) - 1,
      MSSMEB.chg.USD = MSSMEB.USD / lag(MSSMEB.USD) - 1
    ) %>%
    select(Year, Month, contains(".chg")) %>%
    filter(Month == month_curr & Year == year_curr) %>% # Delete all changes that are not for the most recent month. Then, delete the month and year columns:
    ungroup() %>%
    select(-c(Month, Year))



  median.chg.overall.3m <- median.chg.overall %>% filter(Month == month_lag_3 & Year == year_lag_3 | Month == month_curr & Year == year_curr)

  median.chg.overall.3m <- median.chg.overall.3m %>%
    ungroup() %>%
    arrange(Year, Month) %>%
    mutate(
      Sorghum.grain.chg = Sorghum.grain / lag(Sorghum.grain) - 1,
      Maize.grain.chg = Maize.grain / lag(Maize.grain) - 1,
      Wheat.flour.chg = Wheat.flour / lag(Wheat.flour) - 1,
      Rice.chg = Rice / lag(Rice) - 1,
      Groundnuts.chg = Groundnuts / lag(Groundnuts) - 1,
      Beans.chg = Beans / lag(Beans) - 1,
      Sugar.chg = Sugar / lag(Sugar) - 1,
      Salt.chg = Salt / lag(Salt) - 1,
      Cooking.oil.chg = Cooking.oil / lag(Cooking.oil) - 1,
      Soap.chg = Soap / lag(Soap) - 1,
      Jerrycan.chg = Jerrycan / lag(Jerrycan) - 1,
      Mosquito.net.chg = Mosquito.net / lag(Mosquito.net) - 1,
      Exercise.book.chg = Exercise.book / lag(Exercise.book) - 1,
      Blanket.chg = Blanket / lag(Blanket) - 1,
      Cooking.pot.chg = Cooking.pot / lag(Cooking.pot) - 1,
      Plastic.sheet.chg = Plastic.sheet / lag(Plastic.sheet) - 1,
      Pole.chg = Pole / lag(Pole) - 1,
      Firewood.chg = Firewood / lag(Firewood) - 1,
      Charcoal.chg = Charcoal / lag(Charcoal) - 1,
      Goat.chg = Goat / lag(Goat) - 1,
      Chicken.chg = Chicken / lag(Chicken) - 1,
      Milling.costs.chg = Milling.costs / lag(Milling.costs) - 1,
      Rubber.rope.chg = Rubber.rope / lag(Rubber.rope) - 1,
      Kanga.chg = Kanga / lag(Kanga) - 1,
      Solar.lamp.chg = Solar.lamp / lag(Solar.lamp) - 1,
      # Aqua.tab.chg = Aqua.tab/lag(Aqua.tab)-1,
      Plastic.bucket.chg = Plastic.bucket / lag(Plastic.bucket) - 1,
      Sanitary.pad.chg = Sanitary.pad / lag(Sanitary.pad) - 1,
      Pen.chg = Pen / lag(Pen) - 1,
      Pencil.chg = Pencil / lag(Pencil) - 1,
      Rubber.chg = Rubber / lag(Rubber) - 1,
      Sharpener.chg = Sharpener / lag(Sharpener) - 1,
      Sleeping.mat.chg = Sleeping.mat / lag(Sleeping.mat) - 1,
      Bamboo.chg = Bamboo / lag(Bamboo) - 1,
      Underwear.chg = Underwear / lag(Underwear) - 1,
      School.bag.chg = School.bag / lag(School.bag) - 1,
      Bra.chg = Bra / lag(Bra) - 1,
      Grass.chg = Grass / lag(Grass) - 1,
      USD.chg = USD / lag(USD) - 1,
      SDG.chg = SDG / lag(SDG) - 1,
      ETB.chg = ETB / lag(ETB) - 1,
      UGX.chg = UGX / lag(UGX) - 1,
      KES.chg = KES / lag(KES) - 1,
      CDF.chg = CDF / lag(CDF) - 1,
      XAF.chg = XAF / lag(XAF) - 1,
      Food.price.index.chg = Food.price.index / lag(Food.price.index) - 1,
      MSSMEB.food.basket.chg = MSSMEB.food.basket / lag(MSSMEB.food.basket) - 1,
      MSSMEB.chg = MSSMEB / lag(MSSMEB) - 1,
      MSSMEB.food.basket.chg.USD = MSSMEB.food.basket.USD / lag(MSSMEB.food.basket.USD) - 1,
      MSSMEB.chg.USD = MSSMEB.USD / lag(MSSMEB.USD) - 1
    ) %>%
    select(Year, Month, contains(".chg")) %>%
    filter(Month == month_curr & Year == year_curr) %>% # Delete all changes that are not for the most recent month. Then, delete the month and year columns:
    ungroup() %>%
    select(-c(Month, Year))


  # Filter out the months for which you want to calculate the longterm changes (this is important to make sure the below aggregation function works correctly):

  median.chg.overall.long <- median.chg.overall %>% filter(Month == month_long & Year == year_long | Month == month_curr & Year == year_curr)


  median.chg.overall.long <- median.chg.overall.long %>%
    ungroup() %>%
    arrange(Year, Month) %>%
    mutate(
      Sorghum.grain.chg = Sorghum.grain / lag(Sorghum.grain) - 1,
      Maize.grain.chg = Maize.grain / lag(Maize.grain) - 1,
      Wheat.flour.chg = Wheat.flour / lag(Wheat.flour) - 1,
      Rice.chg = Rice / lag(Rice) - 1,
      Groundnuts.chg = Groundnuts / lag(Groundnuts) - 1,
      Beans.chg = Beans / lag(Beans) - 1,
      Sugar.chg = Sugar / lag(Sugar) - 1,
      Salt.chg = Salt / lag(Salt) - 1,
      Cooking.oil.chg = Cooking.oil / lag(Cooking.oil) - 1,
      Soap.chg = Soap / lag(Soap) - 1,
      Jerrycan.chg = Jerrycan / lag(Jerrycan) - 1,
      Mosquito.net.chg = Mosquito.net / lag(Mosquito.net) - 1,
      Exercise.book.chg = Exercise.book / lag(Exercise.book) - 1,
      Blanket.chg = Blanket / lag(Blanket) - 1,
      Cooking.pot.chg = Cooking.pot / lag(Cooking.pot) - 1,
      Plastic.sheet.chg = Plastic.sheet / lag(Plastic.sheet) - 1,
      Pole.chg = Pole / lag(Pole) - 1,
      Firewood.chg = Firewood / lag(Firewood) - 1,
      Charcoal.chg = Charcoal / lag(Charcoal) - 1,
      Goat.chg = Goat / lag(Goat) - 1,
      Chicken.chg = Chicken / lag(Chicken) - 1,
      Milling.costs.chg = Milling.costs / lag(Milling.costs) - 1,
      Rubber.rope.chg = Rubber.rope / lag(Rubber.rope) - 1,
      Kanga.chg = Kanga / lag(Kanga) - 1,
      Solar.lamp.chg = Solar.lamp / lag(Solar.lamp) - 1,
      # Aqua.tab.chg = Aqua.tab/lag(Aqua.tab)-1,
      Plastic.bucket.chg = Plastic.bucket / lag(Plastic.bucket) - 1,
      Sanitary.pad.chg = Sanitary.pad / lag(Sanitary.pad) - 1,
      Pen.chg = Pen / lag(Pen) - 1,
      Pencil.chg = Pencil / lag(Pencil) - 1,
      Rubber.chg = Rubber / lag(Rubber) - 1,
      Sharpener.chg = Sharpener / lag(Sharpener) - 1,
      Sleeping.mat.chg = Sleeping.mat / lag(Sleeping.mat) - 1,
      Bamboo.chg = Bamboo / lag(Bamboo) - 1,
      Underwear.chg = Underwear / lag(Underwear) - 1,
      School.bag.chg = School.bag / lag(School.bag) - 1,
      Bra.chg = Bra / lag(Bra) - 1,
      Grass.chg = Grass / lag(Grass) - 1,
      USD.chg = USD / lag(USD) - 1,
      SDG.chg = SDG / lag(SDG) - 1,
      ETB.chg = ETB / lag(ETB) - 1,
      UGX.chg = UGX / lag(UGX) - 1,
      KES.chg = KES / lag(KES) - 1,
      CDF.chg = CDF / lag(CDF) - 1,
      XAF.chg = XAF / lag(XAF) - 1,
      Food.price.index.chg = Food.price.index / lag(Food.price.index) - 1,
      MSSMEB.food.basket.chg = MSSMEB.food.basket / lag(MSSMEB.food.basket) - 1,
      MSSMEB.chg = MSSMEB / lag(MSSMEB) - 1,
      MSSMEB.food.basket.chg.USD = MSSMEB.food.basket.USD / lag(MSSMEB.food.basket.USD) - 1,
      MSSMEB.chg.USD = MSSMEB.USD / lag(MSSMEB.USD) - 1
    ) %>%
    select(Year, Month, contains(".chg")) %>%
    filter(Month == month_curr & Year == year_curr) %>% # Delete all changes that are not for the most recent month. Then, delete the month and year columns:
    ungroup() %>%
    select(-c(Month, Year))

} # end of batch original SSD code


# ============================================== START ENHANCEMENT ===============================================
# Updated by Mohammad Azemi (May 2024)
# 
# The idea is to reduce the number of sheets/tabs in the JMMI analysis.
# The original file contains 79 tightly connected tabs.
# I tried to trace the Excel formulas and recreated them using R.
# However, some tabs still use Excel formulas in the output files.
# 
# To reduce the tabs, three approaches have been implemented:
#   1) Eliminating intermediate sheets by generating the data directly with R.
#   2) Merging small sheets.
#   3) Splitting the file into two separate files.
#   4) Hiding intermediate sheets that remain in the output files.
#
# result1 has 17 tabs
# result2 has 6 tabs


  # general headers:
  location.headers <- c("state", "county", "location")
  location.headers.capital <- c("State", "County", "Location")
  
  # detect state rows for some sheets like "Table - Median all" and "Table - Stock"
  state_rows_fun <- function(state_column) {
    first_occurrences <- which(!duplicated(state_column))
    increments <- 1:length(first_occurrences)
    first_occurrences <- first_occurrences + increments
    return(first_occurrences)
  }                               
  
  # ---- median and median USD sheets: ---- 
  # these are the column names fixed in the median sheet:
  col.names.part1 <- c(
    "Sorghum.grain", "Maize.grain", "Wheat.flour", "Rice", "Groundnuts", "Beans", "Sugar", "Salt",
    "Cooking.oil", "Soap", "Jerrycan", "Mosquito.net", "Exercise.book", "Blanket", "Cooking.pot", "Plastic.sheet",
    "Pole", "Firewood", "Charcoal", "Goat", "Chicken", "Milling.costs", "Rubber.rope", "Kanga", "Solar.lamp",
    "Plastic.bucket", "Sanitary.pad", "Pen", "Pencil", "Rubber", "Sharpener", "Sleeping.mat", 
    "USD", "SDG", "ETB", "UGX", "KES", "CDF", "XAF"
  )
  
  col.names.part2 <- c(
    "Food.price.index", "MSSMEB.food.basket",	"MSSMEB"
  ) 
 
  col.names.part3 <- c(
    "Covid.price.index", "Cereal"
  ) 
  
  col.names.part4 <- c(
    "Bamboo", "Grass", "Underwear", "School.bag", "Bra"
  ) 
  
  length(col.names.part1) + length(col.names.part2) + length(col.names.part3) + length(col.names.part4)

  median2 <- data.frame()
  median2 <- median
  
  median2 <- median2[, c(location.headers.capital, col.names.part1, col.names.part4)]
  
  median.change <- rbind(median.chg.overall.long, median.chg.overall.1m)
  median.change <- median.change %>% select(-c("MSSMEB.food.basket.chg.USD", "MSSMEB.chg.USD"))

  median.change$Covid.price.index <- NA
  median.change$Cereal <- NA
  
  colnames(median.change) <- gsub(".chg", "", colnames(median.change))
  median.change <- median.change[, c(
    col.names.part1,
    col.names.part2,
    col.names.part3,
    col.names.part4
  )]

  # a function that return a default value which is the overall median value in our case
  get_default_value <- function(df, column_name) {
    default_value <- df[[column_name]][1]
    return(default_value)
  }

  # new overall median:
  median.overall <- data.frame()
  median.overall <- jmmi %>%
    select(
      sorghum_grain_price_unit_ssp, maize_grain_price_unit_ssp, wheat_flour_price_unit_ssp, rice_price_unit_ssp,
      groundnuts_price_unit_ssp, beans_price_unit_ssp, sugar_price_unit_ssp, salt_price_unit_ssp, cooking_oil_price_unit_ssp, soap_price_unit_ssp,
      jerrycan_price_unit_ssp, mosquito_net_price_unit_ssp, exercise_book_price_unit_ssp, blanket_price_unit_ssp, cooking_pot_price_unit_ssp,
      plastic_sheet_price_unit_ssp, pole_price_unit_ssp, firewood_price_unit_ssp, charcoal_price_unit_ssp, goat_price_unit_ssp, chicken_price_unit_ssp,
      grinding_costs_ssp,
      usd_price_ind, sdg_price_ind, etb_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit_ssp, kanga_price_unit_ssp, solar_lamp_price_unit_ssp,
      plastic_bucket_price_unit_ssp, sanitary_pads_price_unit_ssp, pen_price_unit_ssp, pencil_price_unit_ssp, rubber_price_unit_ssp, sharpener_price_unit_ssp,
      sleeping_mat_price_unit_ssp, bamboo_price_unit_ssp, underwear_price_unit_ssp, school_bag_price_unit_ssp, bra_price_unit_ssp, grass_price_unit_ssp
    ) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))
  
  # Rename the column headers:
  median.overall <- median.overall %>%
    rename(
      "Sorghum.grain" = sorghum_grain_price_unit_ssp, "Maize.grain" = maize_grain_price_unit_ssp,
      "Wheat.flour" = wheat_flour_price_unit_ssp, Rice = rice_price_unit_ssp, Groundnuts = groundnuts_price_unit_ssp, Beans = beans_price_unit_ssp,
      Sugar = sugar_price_unit_ssp, Salt = salt_price_unit_ssp, "Cooking.oil" = cooking_oil_price_unit_ssp, Soap = soap_price_unit_ssp, Jerrycan = jerrycan_price_unit_ssp,
      "Mosquito.net" = mosquito_net_price_unit_ssp, "Exercise.book" = exercise_book_price_unit_ssp, Blanket = blanket_price_unit_ssp, "Cooking.pot" = cooking_pot_price_unit_ssp,
      "Plastic.sheet" = plastic_sheet_price_unit_ssp, Pole = pole_price_unit_ssp, Firewood = firewood_price_unit_ssp, Charcoal = charcoal_price_unit_ssp, Goat = goat_price_unit_ssp,
      Chicken = chicken_price_unit_ssp, "Milling.costs" = grinding_costs_ssp, "USD" = usd_price_ind, "SDG" = sdg_price_ind,
      ETB = etb_price_ind, UGX = ugx_price_ind, KES = kes_price_ind, CDF = cdf_price_ind, XAF = xaf_price_ind,
      "Rubber.rope" = rubber_rope_price_unit_ssp, "Kanga" = kanga_price_unit_ssp, "Solar.lamp" = solar_lamp_price_unit_ssp,
      "Plastic.bucket" = plastic_bucket_price_unit_ssp,
      "Sanitary.pad" = sanitary_pads_price_unit_ssp, "Pen" = pen_price_unit_ssp, "Pencil" = pencil_price_unit_ssp, "Rubber" = rubber_price_unit_ssp, "Sharpener" = sharpener_price_unit_ssp,
      "Sleeping.mat" = sleeping_mat_price_unit_ssp, "Bamboo" = bamboo_price_unit_ssp, "Underwear" = underwear_price_unit_ssp, "School.bag" = school_bag_price_unit_ssp, "Bra" = bra_price_unit_ssp,
      "Grass" = grass_price_unit_ssp
    )
  
  median2 <- median2 %>%
    rowwise() %>%
    mutate(
      Food.price.index = sum(
        if_else(!is.na(Sorghum.grain), Sorghum.grain, get_default_value(median.overall, "Sorghum.grain")),
        if_else(!is.na(Maize.grain), Maize.grain, get_default_value(median.overall, "Maize.grain")),
        if_else(!is.na(Wheat.flour), Wheat.flour, get_default_value(median.overall, "Wheat.flour")),
        if_else(!is.na(Rice), Rice, get_default_value(median.overall, "Rice")),
        if_else(!is.na(Groundnuts), Groundnuts, get_default_value(median.overall, "Groundnuts")),
        if_else(!is.na(Beans), Beans, get_default_value(median.overall, "Beans")),
        if_else(!is.na(Sugar), Sugar, get_default_value(median.overall, "Sugar")),
        if_else(!is.na(Salt), Salt, get_default_value(median.overall, "Salt")),
        if_else(!is.na(Cooking.oil), Cooking.oil, get_default_value(median.overall, "Cooking.oil")),
        na.rm = TRUE
      ),
      Cereal = case_when(
        substr(State, nchar(State) - 8, nchar(State)) == "Equatoria" ~ if_else(!is.na(Maize.grain), Maize.grain, get_default_value(median.overall, "Maize.grain")),
        TRUE ~ if_else(!is.na(Sorghum.grain), Sorghum.grain, get_default_value(median.overall, "Sorghum.grain")),
      ),
      MSSMEB.food.basket = sum(
        Cereal * 90,
        if_else(!is.na(Beans), Beans, get_default_value(median.overall, "Beans")) * 9,
        if_else(!is.na(Cooking.oil), Cooking.oil, get_default_value(median.overall, "Cooking.oil")) * 6,
        if_else(!is.na(Salt), Salt, get_default_value(median.overall, "Salt"))
      ),
      MSSMEB = sum(
        MSSMEB.food.basket,
        if_else(!is.na(Soap), Soap, get_default_value(median.overall, "Soap")) * 6,
        if_else(!is.na(Charcoal), Charcoal, get_default_value(median.overall, "Charcoal")) * 50,
        if_else(!is.na(Milling.costs), Milling.costs, get_default_value(median.overall, "Milling.costs")) * 30,
        (MSSMEB.food.basket +
          if_else(!is.na(Soap), Soap, get_default_value(median.overall, "Soap")) * 6 +
          if_else(!is.na(Charcoal), Charcoal, get_default_value(median.overall, "Charcoal")) * 50 +
          if_else(!is.na(Milling.costs), Milling.costs, get_default_value(median.overall, "Milling.costs")) * 30) * 0.05
      ),
      Covid.price.index = sum(
        if_else(!is.na(Sorghum.grain), Sorghum.grain, get_default_value(median.overall, "Sorghum.grain")),
        if_else(!is.na(Maize.grain), Maize.grain, get_default_value(median.overall, "Maize.grain")),
        if_else(!is.na(Rice), Rice, get_default_value(median.overall, "Rice")),
        if_else(!is.na(Sugar), Sugar, get_default_value(median.overall, "Sugar")),
        if_else(!is.na(Soap), Soap, get_default_value(median.overall, "Soap")),
        na.rm = TRUE
      )
    )


  median_Food_price_index <- median(median2$Food.price.index, na.rm = TRUE)
  median_MSSMEB_food_basket <- median(median2$MSSMEB.food.basket, na.rm = TRUE)
  median_MSSMEB <- median(median2$MSSMEB, na.rm = TRUE)
  median.overall$Food.price.index <- median_Food_price_index
  median.overall$MSSMEB.food.basket <- median_MSSMEB_food_basket
  median.overall$MSSMEB <- median_MSSMEB
  median.overall$Covid.price.index <- NA
  median.overall$Cereal <- NA
 
  # final column alignment:
  median.overall <- median.overall[, c(col.names.part1, col.names.part2, col.names.part3, col.names.part4)]
  median.change <- median.change[, c(col.names.part1, col.names.part2, col.names.part3, col.names.part4)]
  median2 <- median2[, c(location.headers.capital, col.names.part1, col.names.part2, col.names.part3, col.names.part4)]
  
  
  # usd info
  not.in.usd <- c(
    "SDG",
    "ETB",
    "UGX",
    "KES",
    "CDF",
    "XAF",
    "Covid.price.index",
    "Cereal" 
  )
  
  median.usd <- data.frame()
  median.usd <- median2 %>% select(-all_of(not.in.usd))
  median_usd_value <- median(median.usd$USD, na.rm = TRUE)
  median.usd$USD[is.na(median.usd$USD)] <- median_usd_value
  numeric_columns <- which(sapply(median.usd, is.numeric))
  median.usd[, numeric_columns] <- round(median.usd[, numeric_columns] / median.usd$USD, digits = 3)
  median.usd.overall <- data.frame()
  median.usd.overall <- median.overall %>% select(-all_of(not.in.usd))
  numeric_columns_overall <- which(sapply(median.usd.overall, is.numeric))
  median.usd.overall[, numeric_columns_overall] <- round(median.usd.overall[, numeric_columns_overall] / median_usd_value, digits = 3)

  # ---- min-max sheet: ---- 
  # a function to replace Inf and -Inf with NA
  replace_inf_with_na <- function(x) {
    x[is.infinite(x)] <- NA
    return(x)
  }
  
  # a function to calculate the difference for each column
  calc_diff <- function(min_col, max_col) {
    round((max_col - min_col) / min_col, 2)
  }
  
  min.tmp <- min
  max.tmp <- max
  
  colnames(min.tmp) <- gsub("_price_unit_ssp", "", colnames(min.tmp))
  colnames(max.tmp) <- gsub("_price_unit_ssp", "", colnames(max.tmp))
  
  # to make sure columns are aligned with the empty template file:
  minmax.col.order <- c(
    location.headers, "sorghum_grain", "maize_grain", "wheat_flour", "rice", "groundnuts",
    "beans", "sugar", "salt", "cooking_oil", "soap", "jerrycan", "mosquito_net", "exercise_book",
    "blanket", "cooking_pot", "plastic_sheet", "pole", "firewood", "charcoal", "goat", "chicken",
    "grinding_costs_ssp", "rubber_rope", "kanga", "solar_lamp", "plastic_bucket", "sanitary_pads",
    "pen", "pencil", "rubber", "sharpener", "sleeping_mat",
    "usd_price_ind", "sdg_price_ind", "etb_price_ind", "ugx_price_ind", "kes_price_ind",
    "cdf_price_ind", "xaf_price_ind",
    "bamboo",  "grass", "underwear", "school_bag", "bra"
  )
  
  min.tmp <- min.tmp[ , minmax.col.order]
  max.tmp <- max.tmp[ , minmax.col.order]
  
  min.tmp[] <- lapply(min.tmp, replace_inf_with_na)
  max.tmp[] <- lapply(max.tmp, replace_inf_with_na)

  # improved approach:
  merged_df <- merge(min.tmp, max.tmp, by = location.headers , suffixes = c(".min", ".max"))
  
  # Create the final data frame with min, max, and diff values
  min.max <- data.frame()
  min.max <- merged_df[location.headers]
  
  for (col in setdiff(names(min.tmp), location.headers)) {
    min_col_name <- paste0(col, ".min")
    max_col_name <- paste0(col, ".max")
    diff_col_name <- paste0("diff.", col)
    
    min.max[[min_col_name]] <- merged_df[[min_col_name]]
    min.max[[max_col_name]] <- merged_df[[max_col_name]]
    min.max[[diff_col_name]] <- calc_diff(merged_df[[min_col_name]], merged_df[[max_col_name]])
  }
  
  # ---- median wholesale sheet: ----  
  median.wholesale.overall <- jmmi %>%
    select(
      sorghum_grain_wholesale_price_unit_ssp, maize_grain_wholesale_price_unit_ssp,
      beans_wholesale_price_unit_ssp, sugar_wholesale_price_unit_ssp
    ) %>%
    summarise(across(everything(), ~ median(., na.rm = TRUE)))

  median.wholesale.overall <- median.wholesale.overall %>%
    rename(
      "Sorghum.grain" = sorghum_grain_wholesale_price_unit_ssp,
      "Maize.grain" = maize_grain_wholesale_price_unit_ssp, "Beans" = beans_wholesale_price_unit_ssp, "Sugar" = sugar_wholesale_price_unit_ssp
    )

  median.overall.tmp <- median.overall %>% select(Sorghum.grain, Maize.grain, Beans, Sugar)
  median.overall.tmp2 <- median.overall.tmp %>% mutate_all(~ . * 50)

  median.wholesale.overall2 <- rbind(median.wholesale.overall, median.overall.tmp2)
  median.wholesale.overall2[3, ] <- round((median.wholesale.overall2[2, ] / median.wholesale.overall2[1, ]) - 1, 2)
  headers3 <- c(
    "MEDIAN (wholesaler)",
    "MEDIAN (retail)",
    "Mark up"
  )

  # ---- road_border sheet (road): ----
  road.header <- c(
    "road",
    "trader",
    "feedback",
    "trader.restrictions",
    "feedback.restrictions"
  )
  road2 <- t(road)
  road2 <- cbind(row_names = rownames(road2), road2)
  rownames(road2) <- NULL
  colnames(road2) <- road.header
  road2 <- as.data.frame(road2)

  road2 <- road2 %>% mutate(
    overall = case_when(
      nchar(as.character(trader)) > 0 ~ trader,
      TRUE ~ feedback
    )
  )

  # ---- road_border sheet: (border): ---- 
  border2 <- NA
  border.header <- c(
    "Border crossing",
    "Trader",
    "Feedback",
    "Quarantine Measures",
    "Extra length of restock (days)"
  )
  border2 <- t(border)
  border2 <- cbind(row_names = rownames(border2), border2)
  rownames(border2) <- NULL
  colnames(border2) <- border.header
  border2 <- as.data.frame(border2)

  border2 <- border2 %>% mutate(
    overall = case_when(
      nchar(as.character(Trader)) > 0 ~ Trader,
      TRUE ~ Feedback
    )
  )

  border2 <- border2 %>% left_join(borders.geo.info, by = c("Border crossing" = "border"))
  borders_plot <- ggplot() +
    geom_sf(data = shapefile, fill = "white", color = "black") +
    geom_point(data = border2, aes(x = Longitude, y = Latitude, fill = overall), size = 1, shape = 22) +
    scale_fill_manual(values = c("open" = "green", "irregular" = "yellow", "closed" = "red")) +
    theme_minimal() +
    theme(
      axis.line = element_blank(),
      axis.text = element_blank(),
      axis.ticks = element_blank(),
      panel.grid = element_blank(),
      axis.title = element_blank(),
      legend.title = element_blank()
    )
  
  # save the map as a png picture:
  ggsave("border_map.png", plot = borders_plot)
  border2 <- border2 %>% select(-c(Latitude, Longitude))

  # ---- median etb sheet: ----
  median.etb.overall <- data.frame()
  median.etb.overall <- jmmi %>%
    filter(currency %in% "ETB") %>%
    select(
      state, county, location, sorghum_grain_price_unit, maize_grain_price_unit,
      wheat_flour_price_unit, rice_price_unit, groundnuts_price_unit,
      beans_price_unit, sugar_price_unit, salt_price_unit, cooking_oil_price_unit,
      soap_price_unit, jerrycan_price_unit, mosquito_net_price_unit, exercise_book_price_unit,
      blanket_price_unit, cooking_pot_price_unit, plastic_sheet_price_unit, pole_price_unit,
      firewood_price_unit, charcoal_price_unit, goat_price_unit, chicken_price_unit, grinding_costs_sorghum_calc,
      usd_price_ind, sdg_price_ind, ugx_price_ind, kes_price_ind, cdf_price_ind, xaf_price_ind,
      rubber_rope_price_unit, kanga_price_unit, solar_lamp_price_unit,
      plastic_bucket_price_unit,
      sanitary_pads_price_unit, pen_price_unit, pencil_price_unit, rubber_price_unit, sharpener_price_unit,
      sleeping_mat_price_unit, bamboo_price_unit, underwear_price_unit, school_bag_price_unit, bra_price_unit, grass_price_unit
    ) %>%
    summarise(across(.cols = 4:last_col(), .fns = ~ median(., na.rm = TRUE)))

  median.etb.overall <- median.etb.overall %>%
    rename(
      "Sorghum.grain.etb" = sorghum_grain_price_unit, "Maize.grain.etb" = maize_grain_price_unit,
      "Wheat.flour.etb" = wheat_flour_price_unit, "Rice.etb" = rice_price_unit, "Groundnuts.etb" = groundnuts_price_unit, "Beans.etb" = beans_price_unit,
      "Sugar.etb" = sugar_price_unit, "Salt.etb" = salt_price_unit, "Cooking.oil.etb" = cooking_oil_price_unit, "Soap.etb" = soap_price_unit, "Jerrycan.etb" = jerrycan_price_unit,
      "Mosquito.net.etb" = mosquito_net_price_unit, "Exercise.book.etb" = exercise_book_price_unit, "Blanket.etb" = blanket_price_unit, "Cooking.pot.etb" = cooking_pot_price_unit,
      "Plastic.sheet.etb" = plastic_sheet_price_unit, "Pole.etb" = pole_price_unit, "Firewood.etb" = firewood_price_unit, "Charcoal.etb" = charcoal_price_unit, "Goat.etb" = goat_price_unit,
      "Chicken.etb" = chicken_price_unit, "Milling.costs.etb" = grinding_costs_sorghum_calc, "USD.etb" = usd_price_ind, "SDG.etb" = sdg_price_ind,
      "UGX.etb" = ugx_price_ind, "KES.etb" = kes_price_ind, "CDF.etb" = cdf_price_ind, "XAF.etb" = xaf_price_ind,
      "Rubber.rope.etb" = rubber_rope_price_unit, "Kanga.etb" = kanga_price_unit, "Solar.lamp.etb" = solar_lamp_price_unit,
      "Plastic.bucket.etb" = plastic_bucket_price_unit,
      "Sanitary.pad.etb" = sanitary_pads_price_unit, "Pen.etb" = pen_price_unit, "Pencil.etb" = pencil_price_unit, "Rubber.etb" = rubber_price_unit, "Sharpener.etb" = sharpener_price_unit,
      "Sleeping.mat.etb" = sleeping_mat_price_unit, "Bamboo.etb" = bamboo_price_unit, "Underwear.etb" = underwear_price_unit, "School.bag.etb" = school_bag_price_unit, "Bra.etb" = bra_price_unit,
      "Grass.etb" = grass_price_unit
    )

  median.etb.full <- bind_rows(median.etb.overall, median.etb)
  median.etb.full <- median.etb.full[, names(median.etb)]

  # ---- stock_level sheet: ----
  stock_level_rounded <- stock_level %>% mutate_if(is.numeric, round)
  
  # ---- Table - combined (items): ----
  get_first_row_value <- function(df, col_name) {
    if (!col_name %in% colnames(df)) {
      return(NA_real_)
    }
    value <- df[1, col_name]

    return(round(as.numeric(value), 2))
  }

  food.items.name <- c(
    "Sorghum.grain", "Maize.grain", "Wheat.flour", "Rice",
    "Groundnuts", "Beans", "Sugar", "Salt", "Cooking.oil"
  )

  non.food.items.name <- c(
    "Soap", "Jerrycan", "Mosquito.net", "Exercise.book", "Blanket", "Cooking.pot", "Plastic.sheet", "Pole",
    "Firewood", "Charcoal", "Rubber.rope", "Kanga", "Solar.lamp", "Plastic.bucket", "Sanitary.pad", "Pen",
    "Pencil", "Rubber", "Sharpener", "Sleeping.mat", "Bamboo", "Underwear", "School.bag", "Bra", "Grass"
  )

  livestock.items.name <- c(
    "Goat", "Chicken"
    )

  services.items.name <- c(
    "Milling.costs"
    )

  currencies.items.name <- c(
    "USD", "SDG", "ETB",
    "UGX", "KES"
  )

  median.chg.overall.1m.tmp <- median.chg.overall.1m
  median.chg.overall.long.tmp <- median.chg.overall.long

  colnames(median.chg.overall.1m.tmp) <- gsub(".chg", "", colnames(median.chg.overall.1m.tmp))
  colnames(median.chg.overall.long.tmp) <- gsub(".chg", "", colnames(median.chg.overall.long.tmp))

  # 1: Food Items
  food.data <- data.frame(
    item_names = character(),
    median_val = numeric(),
    change1_val = numeric(),
    change6_val = numeric(),
    median_usd_val = numeric(),
    stringsAsFactors = FALSE
  )

  for (food_item in food.items.name) {
    food.data <- rbind(food.data, data.frame(
      item_names = food_item,
      median_val = get_first_row_value(median.overall, food_item),
      change1_val = get_first_row_value(median.chg.overall.1m.tmp, food_item),
      change6_val = get_first_row_value(median.chg.overall.long.tmp, food_item),
      median_usd_val = get_first_row_value(median.usd.overall, food_item),
      stringsAsFactors = FALSE
    ))
  }

  # 2: Non-Food Items
  non.food.data <- data.frame(
    item_names = character(),
    median_val = numeric(),
    change1_val = numeric(),
    change6_val = numeric(),
    median_usd_val = numeric(),
    stringsAsFactors = FALSE
  )

  for (non.food_item in non.food.items.name) {
    non.food.data <- rbind(non.food.data, data.frame(
      item_names = non.food_item,
      median_val = get_first_row_value(median.overall, non.food_item),
      change1_val = get_first_row_value(median.chg.overall.1m.tmp, non.food_item),
      change6_val = get_first_row_value(median.chg.overall.long.tmp, non.food_item),
      median_usd_val = get_first_row_value(median.usd.overall, non.food_item),
      stringsAsFactors = FALSE
    ))
  }

  # 3: Livestock Items
  livestock.data <- data.frame(
    item_names = character(),
    median_val = numeric(),
    change1_val = numeric(),
    change6_val = numeric(),
    median_usd_val = numeric(),
    stringsAsFactors = FALSE
  )

  for (livestock_item in livestock.items.name) {
    livestock.data <- rbind(livestock.data, data.frame(
      item_names = livestock_item,
      median_val = get_first_row_value(median.overall, livestock_item),
      change1_val = get_first_row_value(median.chg.overall.1m.tmp, livestock_item),
      change6_val = get_first_row_value(median.chg.overall.long.tmp, livestock_item),
      median_usd_val = get_first_row_value(median.usd.overall, livestock_item),
      stringsAsFactors = FALSE
    ))
  }

  # 4: Service Items
  service.data <- data.frame(
    item_names = character(),
    median_val = numeric(),
    change1_val = numeric(),
    change6_val = numeric(),
    median_usd_val = numeric(),
    stringsAsFactors = FALSE
  )

  for (services_item in services.items.name) {
    service.data <- rbind(service.data, data.frame(
      item_names = services_item,
      median_val = get_first_row_value(median.overall, services_item),
      change1_val = get_first_row_value(median.chg.overall.1m.tmp, services_item),
      change6_val = get_first_row_value(median.chg.overall.long.tmp, services_item),
      median_usd_val = get_first_row_value(median.usd.overall, services_item),
      stringsAsFactors = FALSE
    ))
  }

  # 5: Currencies Items
  currencies.data <- data.frame(
    item_names = character(),
    median_val = numeric(),
    change1_val = numeric(),
    change6_val = numeric(),
    median_usd_val = numeric(),
    stringsAsFactors = FALSE
  )

  for (services_item in currencies.items.name) {
    currencies.data <- rbind(currencies.data, data.frame(
      item_names = services_item,
      median_val = get_first_row_value(median.overall, services_item),
      change1_val = get_first_row_value(median.chg.overall.1m.tmp, services_item),
      change6_val = get_first_row_value(median.chg.overall.long.tmp, services_item),
      median_usd_val = get_first_row_value(median.usd.overall, services_item),
      stringsAsFactors = FALSE
    ))
  }


  # ---- Table - combined (MSSMEB): ----
  # 1) overall MSSMEB:
  median.mssmeb.overall <- median.overall %>% select(MSSMEB)
  median.mssmeb.overall.usd <- median.usd.overall %>% select(usd=MSSMEB)
  median.mssmeb.overall <- cbind(median.mssmeb.overall, median.mssmeb.overall.usd)
  median.mssmeb.1m.overall <- median.chg.overall.1m %>% select(m1 = MSSMEB.chg)
  median.mssmeb.long.overall <- median.chg.overall.long %>% select(m6 = MSSMEB.chg)
  
  median.mssmeb.overall.full <- cbind(median.mssmeb.overall, median.mssmeb.1m.overall)
  median.mssmeb.overall.full <- cbind(median.mssmeb.overall.full, median.mssmeb.long.overall)
  
  median.mssmeb.overall.full <- median.mssmeb.overall.full %>%
    select(
      MSSMEB,
      m1,
      m6,
      usd
    )
  
  # 2) for each location:
  median.mssmeb <- median2 %>% select(State, County, Location, MSSMEB)
  median.mssmeb.usd <- median.usd %>% ungroup() %>% select(County, Location, usd = MSSMEB)
  median.mssmeb.1m <- median.chg.1m  %>% ungroup() %>% select(County, Location, m1 = MSSMEB.chg)
  median.mssmeb.long <- median.chg.long %>% ungroup() %>% select(County, Location, m6 = MSSMEB.chg)
  
  median.mssmeb.full <- left_join(median.mssmeb, median.mssmeb.usd, by = c("County" = "County", "Location" = "Location")) %>%
    left_join(median.mssmeb.1m, by = c("County" = "County", "Location" = "Location")) %>%
    left_join(median.mssmeb.long, by = c("County" = "County", "Location" = "Location"))
  
  median.mssmeb.full <- median.mssmeb.full %>% ungroup()
  median.mssmeb.full <- median.mssmeb.full %>%
    select(
      State, County, Location,
      MSSMEB,
      m1,
      m6,
      usd
    )
  
  result.mssmeb <- data.frame(
    County = character(),
    Location = character(),
    MSSMEB = numeric(),
    m1 = numeric(),
    m6 = numeric(),
    usd = numeric(),
    stringsAsFactors = FALSE
  )
  
  for (state in unique(median.mssmeb.full$State)) {
    result.mssmeb <- rbind(result.mssmeb, data.frame(
      County = state,
      Location = NA,
      MSSMEB = NA,
      m1 = NA,
      m6 = NA,
      usd = NA,
      stringsAsFactors = FALSE
    ))
    
    # Get all rows for this state and add them to the result.mssmeb
    state_rows <- median.mssmeb.full %>%
      filter(State == state) %>%
      select(
        County, Location,
        MSSMEB, m1,
        m6, usd
      )
    result.mssmeb <- rbind(result.mssmeb, state_rows)
  }
  
  # ---- Table - combined (indices): ----
  # 1) overall indices:
  median.ind.overall <- median.overall %>% select(MSSMEB.food.basket, Food.price.index)
  median.ind.1m.overall <- median.chg.overall.1m %>% select(m1 = MSSMEB.food.basket.chg, f1 = Food.price.index.chg)
  median.ind.long.overall <- median.chg.overall.long %>% select(m6 = MSSMEB.food.basket.chg, f6 = Food.price.index.chg)

  median.ind.overall.full <- cbind(median.ind.overall, median.ind.1m.overall)
  median.ind.overall.full <- cbind(median.ind.overall.full, median.ind.long.overall)

  median.ind.overall.full <- median.ind.overall.full %>%
    select(
      MSSMEB.food.basket,
      m1,
      m6,
      Food.price.index,
      f1,
      f6
    )

  # 2) for each location:
  median.ind <- median2 %>% select(State, County, Location, MSSMEB.food.basket, Food.price.index)
  median.ind.1m <- median.chg.1m %>% select(State, County, Location, MSSMEB.food.basket.chg, Food.price.index.chg)
  median.ind.long <- median.chg.long %>% select(State, County, Location, MSSMEB.food.basket.chg, Food.price.index.chg)

  median.ind.full <- left_join(median.ind, median.ind.1m, by = c("County" = "County", "Location" = "Location")) %>%
    left_join(median.ind.long, by = c("County" = "County", "Location" = "Location"))

  median.ind.full <- median.ind.full %>% select(-c(State, State.y))
  median.ind.full <- median.ind.full %>%
    select(
      State = State.x, County, Location,
      MSSMEB.food.basket,
      MSSMEB.food.basket.chg.x,
      MSSMEB.food.basket.chg.y,
      Food.price.index,
      Food.price.index.chg.x,
      Food.price.index.chg.y
    )

  result.ind <- data.frame(
    County = character(),
    Location = character(),
    MSSMEB.food.basket = numeric(),
    MSSMEB.food.basket.chg.x = numeric(),
    MSSMEB.food.basket.chg.y = numeric(),
    Food.price.index = numeric(),
    Food.price.index.chg.x = numeric(),
    Food.price.index.chg.y = numeric(),
    stringsAsFactors = FALSE
  )

  for (state in unique(median.ind.full$State)) {
    result.ind <- rbind(result.ind, data.frame(
      County = state,
      Location = NA,
      MSSMEB.food.basket = NA,
      MSSMEB.food.basket.chg.x = NA,
      MSSMEB.food.basket.chg.y = NA,
      Food.price.index = NA,
      Food.price.index.chg.x = NA,
      Food.price.index.chg.y = NA,
      stringsAsFactors = FALSE
    ))

    # Get all rows for this state and add them to the result.ind
    state_rows <- median.ind.full %>%
      filter(State == state) %>%
      select(
        County, Location,
        MSSMEB.food.basket, MSSMEB.food.basket.chg.x, MSSMEB.food.basket.chg.y,
        Food.price.index, Food.price.index.chg.x, Food.price.index.chg.y
      )
    result.ind <- rbind(result.ind, state_rows)
  }

  # ----  Table median all sheet: ----  
  
median.table.overall <- median.overall %>% select(
  Sorghum.grain, Maize.grain, Wheat.flour, Rice,
  Groundnuts, Beans, Sugar, Salt,
  Cooking.oil, Soap, Jerrycan, Mosquito.net,
  Exercise.book, Blanket, Cooking.pot, Plastic.sheet,
  Pole, Firewood, Charcoal, Goat,
  Chicken, Milling.costs, Rubber.rope, Kanga,
  Solar.lamp, Plastic.bucket, Sanitary.pad, Pen,
  Pencil, Rubber, Sharpener, Sleeping.mat,
  Bamboo, Grass, Underwear, School.bag,
  Bra
)

median.table <- median2 %>% select(
  State, County, Location, Sorghum.grain,
  Maize.grain, Wheat.flour, Rice,
  Groundnuts, Beans, Sugar,
  Salt, Cooking.oil, Soap,
  Jerrycan, Mosquito.net, Exercise.book,
  Blanket, Cooking.pot, Plastic.sheet,
  Pole, Firewood, Charcoal,
  Goat, Chicken, Milling.costs,
  Rubber.rope, Kanga, Solar.lamp,
  Plastic.bucket, Sanitary.pad, Pen,
  Pencil, Rubber, Sharpener,
  Sleeping.mat, Bamboo, Grass,
  Underwear, School.bag, Bra
) %>% ungroup()

result.table <- data.frame(
  County = character(),
  Location = character(),
  Sorghum.grain = numeric(),
  Maize.grain = numeric(),
  Wheat.flour = numeric(),
  Rice = numeric(),
  Groundnuts = numeric(),
  Beans = numeric(),
  Sugar = numeric(),
  Salt = numeric(),
  Cooking.oil = numeric(),
  Soap = numeric(),
  Jerrycan = numeric(),
  Mosquito.net = numeric(),
  Exercise.book = numeric(),
  Blanket = numeric(),
  Cooking.pot = numeric(),
  Plastic.sheet = numeric(),
  Pole = numeric(),
  Firewood = numeric(),
  Charcoal = numeric(),
  Goat = numeric(),
  Chicken = numeric(),
  Milling.costs = numeric(),
  Rubber.rope = numeric(),
  Kanga = numeric(),
  Solar.lamp = numeric(),
  Plastic.bucket = numeric(),
  Sanitary.pad = numeric(), 
  Pen = numeric(), 
  Pencil = numeric(), 
  Rubber = numeric(),
  Sharpener = numeric(), 
  Sleeping.mat = numeric(), 
  Bamboo = numeric(),
  Grass = numeric(), 
  Underwear = numeric(), 
  School.bag = numeric(), 
  Bra = numeric(),
  
  stringsAsFactors = FALSE
)

for (state in unique(median.table$State)) {
  result.table <- rbind(result.table, data.frame(
    County = state,
    Location = NA,
    Sorghum.grain = NA,
    Maize.grain = NA,
    Wheat.flour = NA,
    Rice = NA,
    Groundnuts = NA,
    Beans = NA,
    Sugar = NA,
    Salt = NA,
    Cooking.oil = NA,
    Soap = NA,
    Jerrycan = NA,
    Mosquito.net = NA,
    Exercise.book = NA,
    Blanket = NA,
    Cooking.pot = NA,
    Plastic.sheet = NA,
    Pole = NA,
    Firewood = NA,
    Charcoal = NA,
    Goat = NA,
    Chicken = NA,
    Milling.costs = NA,
    Rubber.rope = NA,
    Kanga = NA,
    Solar.lamp = NA,
    Plastic.bucket = NA,
    Sanitary.pad = NA, 
    Pen = NA, 
    Pencil = NA, 
    Rubber = NA,
    Sharpener = NA, 
    Sleeping.mat = NA, 
    Bamboo = NA,
    Grass = NA, 
    Underwear = NA, 
    School.bag = NA, 
    Bra = NA,    
    stringsAsFactors = FALSE
  ))

  # Get all rows for this state and add them to the result.table
  state_rows <- median.table %>%
    filter(State == state) %>%
    select(
      County, Location, Sorghum.grain, Maize.grain,
      Wheat.flour, Rice, Groundnuts, Beans,
      Sugar, Salt, Cooking.oil, Soap,
      Jerrycan, Mosquito.net, Exercise.book, Blanket,
      Cooking.pot, Plastic.sheet, Pole, Firewood,
      Charcoal, Goat, Chicken, Milling.costs,
      Rubber.rope, Kanga, Solar.lamp, Plastic.bucket,
      Sanitary.pad, Pen, Pencil, Rubber,
      Sharpener, Sleeping.mat, Bamboo,
      Grass, Underwear, School.bag, Bra
    )
  result.table <- rbind(result.table, state_rows)
}

# ----  Table - Stocks sheet: ----  
stock.headers <- c(
  "state",
  "county",
  "location",
  "sorghum_grain_stock_current",
  "maize_grain_stock_current",
  "wheat_flour_stock_current",
  "rice_stock_current",
  "groundnuts_stock_current",
  "beans_stock_current",
  "sugar_stock_current",
  "salt_stock_current",
  "cooking_oil_stock_current",
  "soap_stock_current",
  "jerrycan_stock_current",
  "mosquito_net_stock_current",
  "exercise_book_stock_current",
  "blanket_stock_current",
  "cooking_pot_stock_current",
  "plastic_sheet_stock_current",
  "sleeping_mat_stock_current",
  "pen_available_stock_current",
  "pencil_available_stock_current",
  "rubber_available_stock_current",
  "sharpener_available_stock_current",
  "rubber_rope_available_stock_current",
  "kanga_available_stock_current",
  "solar_lamp_available_stock_current",
  "plastic_bucket_available_stock_current",
  "sanitary_pads_available_stock_current",
  "underwear_available_stock_current",
  "school_bag_available_stock_current",
  "bra_available_stock_current"
)

stock.table <- stock_level %>% select(stock.headers)
stock.table <- stock.table %>% left_join(restock_duration, by = c("county" = "county", "location" = "location"))
stock.table <- stock.table %>% select(- state.y) %>% rename(state = state.x) %>% ungroup()

result.stock <- data.frame(
  county = character(),
  location = character(),
  sorghum_grain_stock_current = numeric(),
  maize_grain_stock_current = numeric(),
  wheat_flour_stock_current = numeric(),
  rice_stock_current = numeric(),
  groundnuts_stock_current = numeric(),
  beans_stock_current = numeric(),
  sugar_stock_current = numeric(),
  salt_stock_current = numeric(),
  cooking_oil_stock_current = numeric(),
  soap_stock_current = numeric(),
  jerrycan_stock_current = numeric(),
  mosquito_net_stock_current = numeric(),
  exercise_book_stock_current = numeric(),
  blanket_stock_current = numeric(),
  cooking_pot_stock_current = numeric(),
  plastic_sheet_stock_current = numeric(),
  sleeping_mat_stock_current = numeric(),
  pen_available_stock_current = numeric(),
  pencil_available_stock_current = numeric(),
  rubber_available_stock_current = numeric(),
  sharpener_available_stock_current = numeric(),
  rubber_rope_available_stock_current = numeric(),
  kanga_available_stock_current = numeric(),
  solar_lamp_available_stock_current = numeric(),
  plastic_bucket_available_stock_current = numeric(),
  sanitary_pads_available_stock_current = numeric(),
  underwear_available_stock_current = numeric(),
  school_bag_available_stock_current = numeric(),
  bra_available_stock_current = numeric(),
  food_supplier_imported_duration = numeric(),
  food_supplier_local_duration = numeric(),
  nfi_supplier_duration = numeric(),
  stringsAsFactors = FALSE
)

for (st in unique(stock.table$state)) {
  result.stock <- rbind(result.stock, data.frame(
    county = st,
    location = NA,
    sorghum_grain_stock_current = NA,
    maize_grain_stock_current = NA,
    wheat_flour_stock_current = NA,
    rice_stock_current = NA,
    groundnuts_stock_current = NA,
    beans_stock_current = NA,
    sugar_stock_current = NA,
    salt_stock_current = NA,
    cooking_oil_stock_current = NA,
    soap_stock_current = NA,
    jerrycan_stock_current = NA,
    mosquito_net_stock_current = NA,
    exercise_book_stock_current = NA,
    blanket_stock_current = NA,
    cooking_pot_stock_current = NA,
    plastic_sheet_stock_current = NA,
    sleeping_mat_stock_current = NA,
    pen_available_stock_current = NA,
    pencil_available_stock_current = NA,
    rubber_available_stock_current = NA,
    sharpener_available_stock_current = NA,
    rubber_rope_available_stock_current = NA,
    kanga_available_stock_current = NA,
    solar_lamp_available_stock_current = NA,
    plastic_bucket_available_stock_current = NA,
    sanitary_pads_available_stock_current = NA,
    underwear_available_stock_current = NA,
    school_bag_available_stock_current = NA,
    bra_available_stock_current = NA,
    food_supplier_imported_duration = NA,
    food_supplier_local_duration = NA,
    nfi_supplier_duration = NA,
    stringsAsFactors = FALSE
  ))
  
  state_rows <- stock.table %>%
    filter(state == st) %>%
    select(
      county,
      location,
      sorghum_grain_stock_current,
      maize_grain_stock_current,
      wheat_flour_stock_current,
      rice_stock_current,
      groundnuts_stock_current,
      beans_stock_current,
      sugar_stock_current,
      salt_stock_current,
      cooking_oil_stock_current,
      soap_stock_current,
      jerrycan_stock_current,
      mosquito_net_stock_current,
      exercise_book_stock_current,
      blanket_stock_current,
      cooking_pot_stock_current,
      plastic_sheet_stock_current,
      sleeping_mat_stock_current,
      pen_available_stock_current,
      pencil_available_stock_current,
      rubber_available_stock_current,
      sharpener_available_stock_current,
      rubber_rope_available_stock_current,
      kanga_available_stock_current,
      solar_lamp_available_stock_current,
      plastic_bucket_available_stock_current,
      sanitary_pads_available_stock_current,
      underwear_available_stock_current,
      school_bag_available_stock_current,
      bra_available_stock_current,
      food_supplier_imported_duration,
      food_supplier_local_duration,
      nfi_supplier_duration,
    )
  result.stock <- rbind(result.stock, state_rows)
}

# ----  Box plot sheet: ----  
boxplot.columns <- c(
  "sorghum_grain_price_unit_ssp", "maize_grain_price_unit_ssp", "wheat_flour_price_unit_ssp", "rice_price_unit_ssp",
  "groundnuts_price_unit_ssp", "beans_price_unit_ssp", "sugar_price_unit_ssp", "salt_price_unit_ssp", 
  "cooking_oil_price_unit_ssp", "soap_price_unit_ssp", "jerrycan_price_unit_ssp", 
  "mosquito_net_price_unit_ssp", "exercise_book_price_unit_ssp",
  "blanket_price_unit_ssp", "cooking_pot_price_unit_ssp", 
  "plastic_sheet_price_unit_ssp", "pole_price_unit_ssp", 
  "firewood_price_unit_ssp", "charcoal_price_unit_ssp", 
  "goat_price_unit_ssp", "chicken_price_unit_ssp",
  "grinding_costs_ssp", "usd_price_ind"
)

quantile.prices <- jmmi %>%
  select(all_of(boxplot.columns)) %>%
  reframe(
    across(everything(), ~ quantile(., probs = c(0.25, 0.5, 0.75), na.rm = TRUE))
    )

min.prices <- jmmi %>%
  select(all_of(boxplot.columns)) %>%
  summarise(
    across(everything(), ~ min(.[is.finite(.)], na.rm = TRUE))
  )

max.prices <- jmmi %>%
  select(all_of(boxplot.columns)) %>%
  summarise(
    across(everything(), ~ max(.[is.finite(.)], na.rm = TRUE))
  )

plot_data <- bind_rows(min.prices, quantile.prices, max.prices)

plot_data.adeed1 <- plot_data[1,]
plot_data.adeed2 <- plot_data[2,] - plot_data[1,]
plot_data.adeed3 <- plot_data[3,] - plot_data[2,]
plot_data.adeed4 <- plot_data[4,] - plot_data[3,]
plot_data.adeed5 <- plot_data[5,] - plot_data[4,]

plot_data <- bind_rows(
  plot_data,
  plot_data.adeed1, plot_data.adeed2,
  plot_data.adeed3, plot_data.adeed4,
  plot_data.adeed5
)

# ----  load the empty template files: ----

wb1 <- loadWorkbook("./data/JMMI_template1.xlsx")
wb2 <- loadWorkbook("./data/JMMI_template2.xlsx")

options("openxlsx.borderColour" = "#303030")
options("openxlsx.borderStyle" = "thin")
modifyBaseFont(wb1, fontSize = 10, fontColour = "#303030")

percentage_style <- createStyle(numFmt = "0%")

# special style for separating rows for some sheets line "Table - Median all" and "Table - Stock"
seperator_style <- createStyle(fontSize = 8, fgFill = "#909090") 

# a function for setting headers:
set_median_header <- function(sheet_name) {
  if (sheet_name == "median") {
    writeData(wb1, sheet_name, x = "MEDIAN", startCol = 3, startRow = 2)
    writeData(wb1, sheet_name, x = "Six Months change", startCol = 3, startRow = 3)
    writeData(wb1, sheet_name, x = "Monthly change", startCol = 3, startRow = 4)
  } else if (sheet_name == "median USD") {
    writeData(wb1, sheet_name, x = "MEDIAN", startCol = 3, startRow = 2)
  }
}

# writing the relevant data frames into excel file: 
# there are excel sheets that multiple data frames 
writeData(wb1, sheet = "quotation_raw", quotation, colNames = TRUE)
writeData(wb1, sheet = "availability", availability, colNames = TRUE)
writeData(wb1, sheet = "median_chg_1m", median.chg.1m, colNames = TRUE)
writeData(wb1, sheet = "median_chg_3m", median.chg.3m, colNames = TRUE)
writeData(wb1, sheet = "median_chg_long", median.chg.long, colNames = TRUE)
writeData(wb1, sheet = "median_chg_overall", median.chg.overall.1m, colNames = TRUE, startCol = 2)
writeData(wb1, sheet = "median_chg_overall", median.chg.overall.3m, colNames = TRUE, startRow = 4, startCol = 2)
writeData(wb1, sheet = "median_chg_overall", median.chg.overall.long, colNames = TRUE, startRow = 7, startCol = 2)
addStyle(wb1, sheet = "median_chg_overall", style = percentage_style, rows = c(2,5,8), cols = 2:ncol(median.chg.overall.1m), gridExpand = TRUE)
writeData(wb1, sheet = "expectation_price", expectation.price, colNames = TRUE, keepNA = FALSE)
writeData(wb1, sheet = "expectation_price", price_expectations, colNames = TRUE, rowNames = TRUE, startRow = 1, startCol = 8) 
writeData(wb1, sheet = "restock_raw", restock, colNames = TRUE)
writeData(wb1, sheet = "restock_duration", restock_duration, colNames = TRUE)
writeData(wb1, sheet = "supply", supply, colNames = TRUE)
writeData(wb1, sheet = "feedback_raw", feedback.export, colNames = TRUE)
writeData(wb1, sheet = "quotation_feedback", feedback.quotation, colNames = TRUE)
writeData(wb1, sheet = "feedback_availability_raw", feedback.availability, colNames = TRUE, startCol = 1, startRow = 3)
writeData(wb1, sheet = "restock_constraints", restock_constraints_df_2, colNames = TRUE, rowNames = TRUE)
writeData(wb2, sheet = "transport_modalities", transport_matrix, colNames = TRUE, rowNames = TRUE)
writeData(wb2, sheet = "transport_modalities", payment_modalities_df_2, colNames = TRUE, rowNames = TRUE, startCol = 5)
writeData(wb1, sheet = "quote_check", quotation_check_unit, colNames = TRUE, rowNames = FALSE)
writeData(wb2, sheet = "trade", nfi_trade, colNames = TRUE, rowNames = FALSE)
writeData(wb2, sheet = "trade", locally_supplied_trade, colNames = TRUE, rowNames = FALSE, startCol = 9)
writeData(wb2, sheet = "trade", mobile_money_reason, colNames = TRUE, rowNames = FALSE, startCol = 17)

# updated sheets: 

writeData(wb1, "median", median.overall, colNames = FALSE, startRow = 2, startCol = 4)
writeData(wb1, "median", median.change, colNames = FALSE, startRow = 3, startCol = 4)
writeData(wb1, "median", median2, colNames = FALSE, startRow = 5)
set_median_header("median")

# writeData(wb1, "median USD", t(columns_to_keep), colNames = FALSE, startRow = 1, startCol = 1)
writeData(wb1, "median USD", median.usd.overall, colNames = FALSE, startRow = 2, startCol = 4)
writeData(wb1, "median USD", median.usd, colNames = FALSE, startRow = 3)
set_median_header("median USD")

writeData(wb1, "minmax", min.max, colNames = FALSE, startRow = 3, startCol = 1)

for (i in seq(6, 135, by = 3)) {
  addStyle(wb1, sheet = "minmax", style = percentage_style, rows = 3:nrow(min.max), cols = i)
}

writeData(wb1, "median_wholesale", t(location.headers), colNames = FALSE, startRow = 1, startCol = 1)
writeData(wb1, "median_wholesale", headers3, colNames = FALSE, startRow = 2, startCol = 3)
writeData(wb1, "median_wholesale", median.wholesale.overall2, colNames = TRUE, startRow = 1, startCol = 4)
writeData(wb1, "median_wholesale", median.wholesale, colNames = FALSE, startRow = 5, startCol = 1)
writeData(wb2, "road_border", road2, colNames = TRUE, startRow = 1, startCol = 1)
writeData(wb2, "road_border", border2, colNames = TRUE, startRow = 1, startCol = 8)
writeData(wb1, "median ETB", median.etb.full, colNames = TRUE, startRow = 1, startCol = 1)
writeData(wb1, "median ETB", "overal median", colNames = FALSE, startRow = 2, startCol = 3)
writeData(wb1, "stock_level", stock_level_rounded, colNames = TRUE, startRow = 1, startCol = 1)
writeData(wb2, "Table - combined", food.data[, -1], colNames = FALSE, startRow = 4, startCol = 3)
writeData(wb2, "Table - combined", non.food.data[, -1], colNames = FALSE, startRow = 15, startCol = 3)
writeData(wb2, "Table - combined", livestock.data[, -1], colNames = FALSE, startRow = 41, startCol = 3)
writeData(wb2, "Table - combined", service.data[, -1], colNames = FALSE, startRow = 44, startCol = 3)
writeData(wb2, "Table - combined", currencies.data[, -1], colNames = FALSE, startRow = 46, startCol = 3)
writeData(wb2, "Table - combined", result.mssmeb, colNames = FALSE, startRow = 3, startCol = 8)
writeData(wb2, "Table - combined", result.mssmeb, colNames = FALSE, startRow = 3, startCol = 8)
writeData(wb2, "Table - combined", result.ind, colNames = FALSE, startRow = 3, startCol = 15)

# add a costume style for states labels:
state_rows.mssmeb <- state_rows_fun(median.mssmeb.full$State)
for (i in state_rows.mssmeb) {
  addStyle(wb2, sheet = "Table - combined", style = seperator_style, rows = i + 1, cols = 8:13)
}

state_rows.ind.full <- state_rows_fun(median.ind.full$State)
for (i in state_rows.ind.full) {
  addStyle(wb2, sheet = "Table - combined", style = seperator_style, rows = i + 1, cols = 15:22)
}

writeData(wb2, "Table - Median all", result.table, colNames = FALSE, startRow = 2, startCol = 1)
state_rows.median <- state_rows_fun(median.table$State)
for (i in state_rows.median) {
  addStyle(wb2, sheet = "Table - Median all", style = seperator_style, rows = i, cols = 1:39)
}

writeData(wb2, "Table - Stock", result.stock, colNames = FALSE, startRow = 2, startCol = 1)
state_rows.stock <- state_rows_fun(stock.table$state)
for (i in state_rows.stock) {
  addStyle(wb2, sheet = "Table - Stock", style = seperator_style, rows = i, cols = 1:34)
}

writeData(wb1, "boxplot", plot_data, colNames = FALSE, startRow = 2, startCol = 2)

# some of sheets are necessary for dashboard, functionality, etc but we don't need directly,
# therefor all of them should be hidden in the output file.

# hidden sheets:
# availability_ext
# median_wholesale
# feedback_availability
# restock_raw
# quotation_raw
# quotation_feedback
# availability
# feedback_availability_raw
# feedback_raw
# quote_check

for (i in 18:28) {
  sheetVisibility(wb1)[i] <- FALSE 
}

# final results as excel files:
saveWorkbook(wb1, result1.file.path, overwrite = TRUE)
saveWorkbook(wb2, result2.file.path, overwrite = TRUE)

