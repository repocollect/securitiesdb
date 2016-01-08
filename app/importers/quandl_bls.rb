require 'csv'
require 'zip'

class QuandlBlsImporter
  def initialize
    @vendor = DataVendor.first(name: "Quandl")
  end

  def import
    import_bls_employment_and_unemployment
  end

  private

  def log(msg)
    Application.logger.info("#{Time.now} - #{msg}")
  end

  # import BLS datasets from https://www.quandl.com/data/BLSE
  def import_bls_employment_and_unemployment
    # BLSE/CEU0000000001 -> Employment - All employees, thousands; Total nonfarm industry
    # import_quandl_time_series("BLSE", "CEU0000000001")

    import_quandl_time_series_database("BLSE")    # BLS Employment & Unemployment - https://www.quandl.com/data/BLSE
    import_quandl_time_series_database("BLSI")    # BLS Inflation & Prices - https://www.quandl.com/data/BLSI
    import_quandl_time_series_database("BLSB")    # BLS Pay & Benefits - https://www.quandl.com/data/BLSB
    import_quandl_time_series_database("BLSP")    # BLS Productivity - https://www.quandl.com/data/BLSP
  end

  def lookup_time_series(data_vendor, database, dataset)
    TimeSeries.first(data_vendor_id: data_vendor.id, database: database, dataset: dataset)
  end

  def create_time_series(data_vendor, database, dataset, name, description = nil)
    TimeSeries.create(data_vendor_id: data_vendor.id, database: database, dataset: dataset, name: name, description: description)
  end

  def import_quandl_time_series_database(quandl_database_code)
    datasets = get_datasets(quandl_database_code)
    datasets.each {|dataset| import_quandl_dataset(dataset) }
  end

  def import_quandl_time_series(quandl_database_code, quandl_dataset_code)
    quandl_code = "#{quandl_database_code}/#{quandl_dataset_code}"
    dataset = get_dataset(quandl_code)
    import_quandl_dataset(dataset)
  end

  def import_quandl_dataset(dataset)
    log("Importing Quandl dataset #{dataset.database_code}/#{dataset.dataset_code} - #{dataset.name}.")
    ts = lookup_time_series(@vendor, dataset.database_code, dataset.dataset_code) || create_time_series(@vendor, dataset.database_code, dataset.dataset_code, dataset.name, dataset.description)
    if ts
      observation_model_class = case dataset.frequency
        when "daily"
          DailyObservation
        when "weekly"
          WeeklyObservation
        when "monthly"
          MonthlyObservation
        when "quarterly"
          QuarterlyObservation
        when "annual"
          YearlyObservation
        else
          quandl_code = "#{dataset.database_code}/#{dataset.dataset_code}"
          raise "Unknown frequency, #{dataset.frequency}, referenced in Quandl dataset \"#{quandl_code}\"."
      end
      dataset.data.each do |record|
        date = convert_date(record.date)
        create_observation(observation_model_class, ts.id, date, record.value) unless lookup_observation(observation_model_class, ts.id, date)
      end
    end
  end

  # quandl_dataset_code is a name like "BLSE/CEU0000000001"
  def get_dataset(quandl_dataset_code)
    Quandl::Dataset.get(quandl_dataset_code)
  end

  # quandl_database_code is a name like "BLSE"
  def get_datasets(quandl_database_code)
    db = Quandl::Database.get(quandl_database_code)
    total_pages = db.datasets.meta[:total_pages]
    (1..total_pages).reduce([]) do |memo, page_number|
      datasets = db.datasets(params: {page: page_number}).values
      memo.concat(datasets)
    end
  end

  def lookup_observation(observation_model_class, time_series_id, datestamp)
    observation_model_class.first(time_series_id: time_series_id, date: datestamp)
  end

  def create_observation(observation_model_class, time_series_id, datestamp, value)
    observation_model_class.create(time_series_id: time_series_id, date: datestamp, value: value)
  end

  # date is a Date object
  # returns the integer yyyymmdd representation of the given Date object
  def convert_date(date)
    date.strftime("%Y%m%d").to_i if date
  end

end