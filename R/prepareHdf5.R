#'@export
prepareHdf5 <- function(caffedir = "~/Documents/caffe" ,
                        name = "MyModel" ,
                        imagedir = "~/main" ,
                        phase = "train",
                        values = NULL ,
                        image_ids = NULL,
                        suffix = NULL,
                        padding = FALSE,
                        resize_height = 256,
                        resize_width = 256,
                        mean_file = "~/main/image_mean.h5",
                        batch_size = 512) {
  on.exit(closeAllConnections())
  
  if (is.null(image_ids)) {
    stop ("The image ids are required.")
  }
  if (is.null(labels)) {
    stop ("The labels are required.")
  }
  if (is.null(mean_file) || !file.exists(mean_file)) {
    stop(
      "The image mean file does not exist. Please ensure to run computeMeanHdf5 first and that you provided the correct path"
    )
  }
  n <- length(values)
  batch_size <- adjustBatchSize(n, batch_size)
  #Currently the is a limit on the max number of units in caffe -  splitting is required
  INT_MAX <- 2 * 1024 ^ 3 - 1
  max_entries <- floor(INT_MAX / (3 * resize_height * resize_width))
  max_batches <- max(max_entries %/% batch_size, 1)
  
  #Image mean einlesen
  image_mean <- rhdf5::h5read(mean_file, "mean")
  
  # Channel mean supplied
  if (length(image_mean) == 3) {
    temp <- image_mean
    image_mean <-
      array(0, dim = c(resize_width , resize_height , 3))
    image_mean[, , 1:3] <- temp
  }
  if (sum(dim(image_mean) != c(resize_width , resize_height , 3)) > 0) {
    stop("The image mean dimensions are not correct")
  }
  
  if (n > max_entries) {
    num_files <- 1
    file_name <-
      paste0(caffedir, "/data/", name, "/", phase, "_0", num_files, ".h5")
  } else {
    file_name <- paste0(caffedir, "/data/", name, "/", phase, ".h5")
  }
  createHDF5(file_name ,
             resize_height ,
             resize_width ,
             max_batches * batch_size,
             batch_size)
  write(file_name,
        paste0(caffedir, "/data/", name, "/", phase, ".txt"),
        append = FALSE)
  if (n != length(image_ids)) {
    stop("Number of labels and Images do not match")
  }
  image_list <-
    list.files(imagedir, pattern = paste0(suffix, ".jpg"))
  
  if (length(image_list) < length(image_ids)) {
    print(length(image_list))
    print(
      "Some images can't be found in the given directory - Creating images based on supplied image mean"
    )
    generateNewImages (imagedir ,
                       image_ids ,
                       suffix ,
                       image_mean)
  }
  #Initializing batch files
  image_batch <-
    array(0, dim = c(resize_width, resize_height, 3, batch_size))
  label_batch <- array(0, dim = c(1, 1, 1, batch_size))
  
  
  i <- 1
  batch_counter <- 0
  print(paste0("Processing a total of ", n, " images."))
  last_indx <- 1
  for (k in 1:n) {
    image_path <- paste0(imagedir, "/", image_ids[k], suffix, ".jpg")
    image_batch[, , , i] <-
      preprocessImagesHdf5(image_path,
                           padding ,
                           resize_height ,
                           resize_width ,
                           image_mean)
    
    label_batch[, , , i] <- values[k]
    
    
    if (i == batch_size) {
      print(paste0("Saving ", last_indx%/%batch_size+1, ". batch"))
      rhdf5::h5write(
        image_batch,
        file = file_name,
        name = "data",
        index = list(
          1:resize_width,
          1:resize_height,
          1:3,
          last_indx:(last_indx + batch_size - 1)
        )
      )
      rhdf5::h5write(
        label_batch,
        file = file_name,
        name = "label",
        index = list(1:1, 1:1, 1:1, 
                     last_indx:(last_indx + batch_size -1)
                     )
      )
      rhdf5::H5close()
      i <- 0
      last_indx <- last_indx + batch_size
    }
    if (last_indx == max_batches*batch_size+1 && k != n) {
      num_files <- num_files + 1
      file_name <-
        paste0(caffedir,
               "/data/",
               name,
               "/",
               phase,
               "_0",
               num_files,
               ".h5")
      createHDF5(file_name ,
                 resize_height ,
                 resize_width ,
                 max_batches * batch_size,
                 batch_size)
      write(file_name,
            paste0(caffedir, "/data/", name, "/", phase, ".txt"),
            append = TRUE)
      last_indx <- 1
    }
    
    i <- i + 1
    
    if (k %% 1000 == 0) {
      print(paste0("Processed ", k, "images. Only ", n - k, " to go."))
    }
  }
  
  
  
}
#====================================================================================================================================================================
adjustBatchSize <- function(n, batch_size) {
  if (n %% batch_size != 0) {
    adjustBatchSize(n, batch_size - 1)
  } else{
    return(batch_size)
  }
  
}
#=============================================================================================================================
createHDF5 <-
  function(file_name,
           resize_height ,
           resize_width ,
           n ,
           batch_size) {
    rhdf5::h5createFile(file_name)
    #HDF5 file needs to be in WxHxCxN since C interprets the dimensions differently than R
    rhdf5::h5createDataset(
      file_name ,
      "data",
      c(resize_width, resize_height, 3, n),
      storage.mode = "double",
      showWarnings = FALSE,
      chunk = c(resize_width, resize_height, 3, batch_size),
      level = 9
    )
    
    rhdf5::h5createDataset(
      file_name ,
      "label",
      c(1, 1, 1, n),
      chunk = c(1, 1, 1, batch_size),
      storage.mode = "double",
      showWarnings = FALSE,
      level = 9
    )
  }
