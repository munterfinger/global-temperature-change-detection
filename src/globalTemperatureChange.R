# ------------------------------------------------------------------------------
# Change detection in global temperature - universal Kriging
#
# Author: Merlin Unterfinger
# Date: 26.73.17

# Settings and Variables --------------------------------------------------
rm(list=ls())             # Clean the environment
options(scipen=6)         # Display digits, not the scientific version
options(digits.secs=6)    # use milliseconds in Date/Time data types
options(warning=FALSE)    # Don't show warnings
par(mfrow=c(1,1))         # reset plot placement to normal 1 by 1
maxpixels <- 101250       # Plot resolution

# Get paths
setwd('..')
dataFolder    <- file.path(getwd(), "data")                 # Data folder
figureFolder  <- file.path(getwd(), "docs/figures")         # Figure Folder

# Libraries
library(ape)
library(dichromat)
library(FNN)
library(ggplot2) 
library(gdistance)
library(gridExtra)
library(gstat)
library(raster)
library(rasterVis)
library(rgdal)
library(rgeos)
library(sp)


# Data --------------------------------------------------------------------
# Define CRS
WGS84 <- CRS("+init=epsg:4326")

# Read CSV file for temperature
temp <- read.csv(file.path(dataFolder, "temperature.csv"))
temp <- temp[complete.cases(temp), ]

# Train and validation data
selection <- sample(1:nrow(temp), floor(nrow(temp)*0.05), replace = FALSE)
temp.val    <- temp[selection,]
temp  <- temp[-selection,]

# Create spdf's and assign CRS
coordinates(temp.val)<-~long+lat
proj4string(temp.val)<-WGS84
coordinates(temp)<-~long+lat
proj4string(temp)<-WGS84

# Read test file
temp.test <- read.csv(file.path(dataFolder, "temperature_test.csv"))
coordinates(temp.test) <- ~long+lat
proj4string(temp.test) <- WGS84

plot(temp, main="All measurements and validation points")
points(temp.val, col="red")

knitr::kable(head(round(as.data.frame(head(temp)),2), caption = "Structure of the temperature data set.", row.names = FALSE))

# Seperate data according to timeFrame and season
temp1970w <-SpatialPointsDataFrame(coords = temp@coords, data = temp@data[,1:2])
temp1970s <-SpatialPointsDataFrame(coords = temp@coords, data = temp@data[,c(1,3)])
temp2010w <-SpatialPointsDataFrame(coords = temp@coords, data = temp@data[,c(1,4)])
temp2010s <-SpatialPointsDataFrame(coords = temp@coords, data = temp@data[,c(1,5)])

col <- c("id", "meansum")
colnames(temp1970s@data) <- col
colnames(temp2010s@data) <- col
colnames(temp1970w@data) <- col
colnames(temp2010w@data) <- col

# Open digital elevation model
DEM <-readGDAL(file.path(dataFolder, "globalDHM.tif"), silent = T)

# Set up grid, for prediction
grid <- spsample(DEM,type="regular",100)

# Downsize
DEM <- raster(DEM)
#DEM <- aggregate(DEM, fact=5.5)
DEM <- aggregate(DEM, fact=16)

# Extract all only land
landDEM <- DEM
landDEM[landDEM<0] <- 0
grid <- SpatialPointsDataFrame(grid@coords,data.frame(elevation=extract(landDEM,grid)))

# Assign elevation to grid for prediction
grid <- SpatialPointsDataFrame(grid@coords,data.frame(elevation=extract(landDEM,grid)))

# Load coastlines for plotting
oceans <- readOGR(dsn="data", "ne_110m_ocean", verbose=F)

# Plot
p <- levelplot(DEM,
               main = "DEM",
               maxpixels = maxpixels,
               par.settings=rasterTheme(region = dichromat(topo.colors(7))), margin=F,
               at=seq(-maxValue(abs(DEM)), maxValue(abs(DEM)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p)

# Save plots
pdf(file.path(figureFolder, "DEM.pdf"), width=10.5, height=7.5)
print(p)
invisible(dev.off())

# Clear plots
remove(p)

# Spatial continuity ------------------------------------------------------
## H-scatterplots and autocovariance
### Winter before 1970
temp.dist<-spDists(temp1970w,longlat = FALSE)
temp.index <-knn.index(temp.dist, k=20, algorithm=c("kd_tree"))

temp.h<-data.frame(sum=temp1970w$meansum ,sumNN1=temp1970w$meansum[temp.index[,1]],sumNN5=temp1970w$meansum[temp.index[,5]],sumNN10=temp1970w$meansum[temp.index[,10]],sumNN20=temp1970w$meansum[temp.index[,20]])

par(mfrow=c(2,2))
plot(temp.h$sum,temp.h$sumNN1,main="h = 1")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN5,main="h = 5")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN10,main="h = 10")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN20,main="h = 20")
abline(1,1, col = "blue")

# Autocoavariance plots
temp.mean<-mean(temp.h$sum, na.rm = TRUE)
temp.sd<-sd(temp.h$sum, na.rm = TRUE)

temp.acov.nn1<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN1-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn5<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN5-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn10<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN10-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn20<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN20-temp.mean), na.rm = TRUE)/nrow(temp.h)

temp.acorr.nn1<-temp.acov.nn1/temp.sd^2
temp.acorr.nn5<-temp.acov.nn5/temp.sd^2
temp.acorr.nn10<-temp.acov.nn10/temp.sd^2
temp.acorr.nn20<-temp.acov.nn20/temp.sd^2

par(mfrow=c(1,2))
plot(c(1,5,10,20),c(temp.acov.nn1,temp.acov.nn5,temp.acov.nn10,temp.acov.nn20),type="l",main="auto-covariance")
plot(c(1,5,10,20),c(temp.acorr.nn1,temp.acorr.nn5,temp.acorr.nn10,temp.acorr.nn20),type="l",main="auto-correlation")

### Winter after 1990
temp.dist<-spDists(temp2010w,longlat = FALSE)
temp.index <-knn.index(temp.dist, k=20, algorithm=c("kd_tree"))

temp.h<-data.frame(sum=temp2010w$meansum ,sumNN1=temp2010w$meansum[temp.index[,1]],sumNN5=temp2010w$meansum[temp.index[,5]],sumNN10=temp2010w$meansum[temp.index[,10]],sumNN20=temp2010w$meansum[temp.index[,20]])

par(mfrow=c(2,2))
plot(temp.h$sum,temp.h$sumNN1,main="h = 1")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN5,main="h = 5")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN10,main="h = 10")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN20,main="h = 20")
abline(1,1, col = "blue")

# Autocoavariance plots
temp.mean<-mean(temp.h$sum, na.rm = TRUE)
temp.sd<-sd(temp.h$sum, na.rm = TRUE)

temp.acov.nn1<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN1-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn5<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN5-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn10<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN10-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn20<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN20-temp.mean), na.rm = TRUE)/nrow(temp.h)

temp.acorr.nn1<-temp.acov.nn1/temp.sd^2
temp.acorr.nn5<-temp.acov.nn5/temp.sd^2
temp.acorr.nn10<-temp.acov.nn10/temp.sd^2
temp.acorr.nn20<-temp.acov.nn20/temp.sd^2

par(mfrow=c(1,2))
plot(c(1,5,10,20),c(temp.acov.nn1,temp.acov.nn5,temp.acov.nn10,temp.acov.nn20),type="l",main="auto-covariance")
plot(c(1,5,10,20),c(temp.acorr.nn1,temp.acorr.nn5,temp.acorr.nn10,temp.acorr.nn20),type="l",main="auto-correlation")

### Summer before 1970
temp.dist<-spDists(temp1970s,longlat = FALSE)
temp.index <-knn.index(temp.dist, k=20, algorithm=c("kd_tree"))

temp.h<-data.frame(sum=temp1970s$meansum ,sumNN1=temp1970s$meansum[temp.index[,1]],sumNN5=temp1970s$meansum[temp.index[,5]],sumNN10=temp1970s$meansum[temp.index[,10]],sumNN20=temp1970s$meansum[temp.index[,20]])

par(mfrow=c(2,2))
plot(temp.h$sum,temp.h$sumNN1,main="h = 1")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN5,main="h = 5")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN10,main="h = 10")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN20,main="h = 20")
abline(1,1, col = "blue")

# Autocovariance plots
temp.mean <- mean(temp.h$sum, na.rm = TRUE)
temp.sd<-sd(temp.h$sum, na.rm = TRUE)

temp.acov.nn1<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN1-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn5<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN5-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn10<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN10-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn20<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN20-temp.mean), na.rm = TRUE)/nrow(temp.h)

temp.acorr.nn1<-temp.acov.nn1/temp.sd^2
temp.acorr.nn5<-temp.acov.nn5/temp.sd^2
temp.acorr.nn10<-temp.acov.nn10/temp.sd^2
temp.acorr.nn20<-temp.acov.nn20/temp.sd^2

par(mfrow=c(1,2))
plot(c(1,5,10,20),c(temp.acov.nn1,temp.acov.nn5,temp.acov.nn10,temp.acov.nn20),type="l",main="auto-covariance")
plot(c(1,5,10,20),c(temp.acorr.nn1,temp.acorr.nn5,temp.acorr.nn10,temp.acorr.nn20),type="l",main="auto-correlation")

### Summer after 1990
temp.dist<-spDists(temp2010s,longlat = FALSE)
temp.index <-knn.index(temp.dist, k=20, algorithm=c("kd_tree"))

temp.h<-data.frame(sum=temp2010s$meansum ,sumNN1=temp2010s$meansum[temp.index[,1]],sumNN5=temp2010s$meansum[temp.index[,5]],sumNN10=temp2010s$meansum[temp.index[,10]],sumNN20=temp2010s$meansum[temp.index[,20]])

par(mfrow=c(2,2))
plot(temp.h$sum,temp.h$sumNN1,main="h = 1")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN5,main="h = 5")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN10,main="h = 10")
abline(1,1, col = "blue")
plot(temp.h$sum,temp.h$sumNN20,main="h = 20")
abline(1,1, col = "blue")

# Autocoavariance plots
temp.mean<-mean(temp.h$sum, na.rm = TRUE)
temp.sd<-sd(temp.h$sum, na.rm = TRUE)

temp.acov.nn1<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN1-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn5<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN5-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn10<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN10-temp.mean), na.rm = TRUE)/nrow(temp.h)
temp.acov.nn20<-sum((temp.h$sum-temp.mean)*(temp.h$sumNN20-temp.mean), na.rm = TRUE)/nrow(temp.h)

temp.acorr.nn1<-temp.acov.nn1/temp.sd^2
temp.acorr.nn5<-temp.acov.nn5/temp.sd^2
temp.acorr.nn10<-temp.acov.nn10/temp.sd^2
temp.acorr.nn20<-temp.acov.nn20/temp.sd^2

par(mfrow=c(1,2))
plot(c(1,5,10,20),c(temp.acov.nn1,temp.acov.nn5,temp.acov.nn10,temp.acov.nn20),type="l",main="auto-covariance")
plot(c(1,5,10,20),c(temp.acorr.nn1,temp.acorr.nn5,temp.acorr.nn10,temp.acorr.nn20),type="l",main="auto-correlation")

# Empirical Variogram -----------------------------------------------------
### Winter before 1970
temp1970w.var1<-variogram(meansum~1,temp1970w,cutoff=1000,width=1)
temp1970w.var5<-variogram(meansum~1,temp1970w,cutoff=150,width=5)
temp1970w.var10<-variogram(meansum~1,temp1970w,cutoff=150,width=10)
temp1970w.var15<-variogram(meansum~1,temp1970w,cutoff=150,width=15)

grid.arrange(plot(temp1970w.var1, main="Bin width 1km"), 
             plot(temp1970w.var5, main="Bin width 5km"), ncol = 2)

grid.arrange(plot(temp1970w.var10, main="Bin width 10km"), 
             plot(temp1970w.var15, main="Bin width 15km"), ncol = 2)

bws<-data.frame(np=temp1970w.var1$np,bw=rep("1km",length(temp1970w.var1$np)))
bws<-rbind(bws,data.frame(np=temp1970w.var5$np,bw=rep("5km",length(temp1970w.var5$np))))
bws<-rbind(bws,data.frame(np=temp1970w.var10$np,bw=rep("10km",length(temp1970w.var10$np))))
bws<-rbind(bws,data.frame(np=temp1970w.var15$np,bw=rep("15km",length(temp1970w.var15$np))))

#plotting the numbers of points per bin and bandwidth as a boxplot
ggplot(bws, aes(x=bw, y=np, color=bw)) +
  geom_boxplot()

### Winter after 1990
temp2010w.var1<-variogram(meansum~1,temp2010w,cutoff=1000,width=1)
temp2010w.var5<-variogram(meansum~1,temp2010w,cutoff=150,width=5)
temp2010w.var10<-variogram(meansum~1,temp2010w,cutoff=150,width=10)
temp2010w.var15<-variogram(meansum~1,temp2010w,cutoff=150,width=15)

grid.arrange(plot(temp2010w.var1, main="Bin width 1km"), 
             plot(temp2010w.var5, main="Bin width 5km"), ncol = 2)

grid.arrange(plot(temp2010w.var10, main="Bin width 10km"), 
             plot(temp2010w.var15, main="Bin width 15km"), ncol = 2)

bws<-data.frame(np=temp2010w.var1$np,bw=rep("1km",length(temp2010w.var1$np)))
bws<-rbind(bws,data.frame(np=temp2010w.var5$np,bw=rep("5km",length(temp2010w.var5$np))))
bws<-rbind(bws,data.frame(np=temp2010w.var10$np,bw=rep("10km",length(temp2010w.var10$np))))
bws<-rbind(bws,data.frame(np=temp2010w.var15$np,bw=rep("15km",length(temp2010w.var15$np))))

#plotting the numbers of points per bin and bandwidth as a boxplot
ggplot(bws, aes(x=bw, y=np, color=bw)) +
  geom_boxplot()

### Summer before 1970
temp1970s.var1<-variogram(meansum~1,temp1970s,cutoff=1000,width=1)
temp1970s.var5<-variogram(meansum~1,temp1970s,cutoff=150,width=5)
temp1970s.var10<-variogram(meansum~1,temp1970s,cutoff=150,width=10)
temp1970s.var15<-variogram(meansum~1,temp1970s,cutoff=150,width=15)

grid.arrange(plot(temp1970s.var1, main="Bin width 1km"), 
             plot(temp1970s.var5, main="Bin width 5km"), ncol = 2)

grid.arrange(plot(temp1970s.var10, main="Bin width 10km"), 
             plot(temp1970s.var15, main="Bin width 15km"), ncol = 2)

bws<-data.frame(np=temp1970s.var1$np,bw=rep("1km",length(temp1970s.var1$np)))
bws<-rbind(bws,data.frame(np=temp1970s.var5$np,bw=rep("5km",length(temp1970s.var5$np))))
bws<-rbind(bws,data.frame(np=temp1970s.var10$np,bw=rep("10km",length(temp1970s.var10$np))))
bws<-rbind(bws,data.frame(np=temp1970s.var15$np,bw=rep("15km",length(temp1970s.var15$np))))

#plotting the numbers of points per bin and bandwidth as a boxplot
ggplot(bws, aes(x=bw, y=np, color=bw)) +
  geom_boxplot()

### Summer after 1990
temp2010s.var1<-variogram(meansum~1,temp2010s,cutoff=1000,width=1)
temp2010s.var5<-variogram(meansum~1,temp2010s,cutoff=150,width=5)
temp2010s.var10<-variogram(meansum~1,temp2010s,cutoff=150,width=10)
temp2010s.var15<-variogram(meansum~1,temp2010s,cutoff=150,width=15)

grid.arrange(plot(temp2010s.var1, main="Bin width 1km"), 
             plot(temp2010s.var5, main="Bin width 5km"), ncol = 2)

grid.arrange(plot(temp2010s.var10, main="Bin width 10km"), 
             plot(temp2010s.var15, main="Bin width 15km"), ncol = 2)

bws<-data.frame(np=temp2010s.var1$np,bw=rep("1km",length(temp2010s.var1$np)))
bws<-rbind(bws,data.frame(np=temp2010s.var5$np,bw=rep("5km",length(temp2010s.var5$np))))
bws<-rbind(bws,data.frame(np=temp2010s.var10$np,bw=rep("10km",length(temp2010s.var10$np))))
bws<-rbind(bws,data.frame(np=temp2010s.var15$np,bw=rep("15km",length(temp2010s.var15$np))))

#plotting the numbers of points per bin and bandwidth as a boxplot
ggplot(bws, aes(x=bw, y=np, color=bw)) +
  geom_boxplot()

## Fitted Semivariogram
### Winter before 1970
temp1970w.var10<-variogram(meansum~1,temp1970w,cutoff=150,width=10)

models <- c("Exp", "Sph", "Gau", "Mat")
temp1970w.var10.fits <- lapply(X=1:4, FUN=function(x) fit.variogram(temp1970w.var10, model=vgm(models[x])))

grid.arrange(plot(temp1970w.var10, model=temp1970w.var10.fits[[1]], main = "Exponential: 10km"), 
             plot(temp1970w.var10, model=temp1970w.var10.fits[[2]], main = "Spherical: 10km"), ncol = 2)
grid.arrange(plot(temp1970w.var10, model=temp1970w.var10.fits[[3]], main = "Gaussian: 10km"), 
             plot(temp1970w.var10, model=temp1970w.var10.fits[[4]], main = "Mat: 10km"), ncol = 2)

### Winter after 1990
temp2010w.var10<-variogram(meansum~1,temp2010w,cutoff=150,width=10)

models <- c("Exp", "Sph", "Gau", "Mat")
temp2010w.var10.fits <- lapply(X=1:4, FUN=function(x) fit.variogram(temp2010w.var10, model=vgm(models[x])))

grid.arrange(plot(temp2010w.var10, model=temp2010w.var10.fits[[1]], main = "Exponential: 10km"), 
             plot(temp2010w.var10, model=temp2010w.var10.fits[[2]], main = "Spherical: 10km"), ncol = 2)
grid.arrange(plot(temp2010w.var10, model=temp2010w.var10.fits[[3]], main = "Gaussian: 10km"), 
             plot(temp2010w.var10, model=temp2010w.var10.fits[[4]], main = "Mat: 10km"), ncol = 2)

### Summer before 1970
temp1970s.var10<-variogram(meansum~1,temp1970s,cutoff=150,width=10)

models <- c("Exp", "Sph", "Gau", "Mat")
temp1970s.var10.fits <- lapply(X=1:4, FUN=function(x) fit.variogram(temp1970s.var10, model=vgm(models[x])))

grid.arrange(plot(temp1970s.var10, model=temp1970s.var10.fits[[1]], main = "Exponential: 10km"), 
             plot(temp1970s.var10, model=temp1970s.var10.fits[[2]], main = "Spherical: 10km"), ncol = 2)
grid.arrange(plot(temp1970s.var10, model=temp1970s.var10.fits[[3]], main = "Gaussian: 10km"), 
             plot(temp1970s.var10, model=temp1970s.var10.fits[[4]], main = "Mat: 10km"), ncol = 2)

### Summer after 1990
temp2010s.var10<-variogram(meansum~1,temp2010s,cutoff=150,width=10)

models <- c("Exp", "Sph", "Gau", "Mat")
temp2010s.var10.fits <- lapply(X=1:4, FUN=function(x) fit.variogram(temp2010s.var10, model=vgm(models[x])))

grid.arrange(plot(temp2010s.var10, model=temp2010s.var10.fits[[1]], main = "Exponential: 10km"), 
             plot(temp2010s.var10, model=temp2010s.var10.fits[[2]], main = "Spherical: 10km"), ncol = 2)
grid.arrange(plot(temp2010s.var10, model=temp2010s.var10.fits[[3]], main = "Gaussian: 10km"), 
             plot(temp2010s.var10, model=temp2010s.var10.fits[[4]], main = "Mat: 10km"), ncol = 2)

# Universal Kriging -------------------------------------------------------
## Continentality
# Load highres coastlines for distance layer
oceans.50m <- readOGR(dsn="data", "ne_50m_ocean", verbose=F)
# Simplify geometry
oceans.simply <-SpatialPolygonsDataFrame(
  gSimplify(oceans.50m, tol=1, topologyPreserve=TRUE),
  data=oceans.50m@data)

# Build blank raster
r <- DEM
r <- setValues(r, 0)
#r <- aggregate(r, fact=10)

# Make values NA where polygon intesects raster
r <- mask(r, oceans.simply)

# Run distance check
ocean.dist <- distance(r)

# # to restrict your search
# searchLimit <- 100 # the maximum distance in raster units from lakes/boundaries
# oceans.simply.buff <- gBuffer(oceans.simply, width = searchLimit, byid = T)
# rB <- crop(r, extent(oceans.simply.buff))
# 
# # much faster...
# rDB <- distance(rB)

# Plot
p <- levelplot(ocean.dist,
               main = "Continentality",
               maxpixels = maxpixels,
               par.settings=YlOrRdTheme(), margin=F, 
               at=seq(0, max(abs(cellStats(ocean.dist, range))), len=100)) + 
  layer(sp.polygons(oceans, fill='black', alpha=1))
print(p)

# Save plot
pdf(file.path(figureFolder, "Continentality.pdf"), width=10.5, height=7.5)
print(p)
invisible(dev.off())

# Remove plot
remove(p)

## Surface gradient (North-South)
# Create latitude and longitude layers
lat <- DEM
lat[] <- coordinates(DEM)[, 2]

# Slope and aspect
slope <- terrain(landDEM, opt='slope', unit='radians')
aspect <- terrain(landDEM, opt='aspect', unit='radians')

# Winter
aPer <- (180/2+23)/180
split.hemi.w <- setValues(lat, 1)
split.hemi.w[1:floor((nrow(lat)*aPer)), 1:ncol(lat)] <- -1

# Summer
aPer <- (180/2-23)/180
split.hemi.s <- setValues(lat, 1)
split.hemi.s[1:floor((nrow(lat)*aPer)), 1:ncol(lat)] <- -1

# Calculate the gradient in latitude direction
latGrad <- (cos(aspect)*slope)*180/pi
latGrad.w <- latGrad*split.hemi.w
latGrad.s <- latGrad*split.hemi.s

# Plot
p1 <- levelplot(latGrad.w,
                main = "North-South gradient, +23.5° hemisphere corrected",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(latGrad.w)), maxValue(abs(latGrad.w)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent', alpha=1))
print(p1)

p2 <- levelplot(latGrad.s,
                main = "North-South gradient, -23.5° hemisphere corrected",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(latGrad.s)), maxValue(abs(latGrad.s)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent', alpha=1))
print(p1)

# Save plots
pdf(file.path(figureFolder, "gradient_WiHemiCorr.pdf"), width=10.5, height=7.5)
print(p1)
invisible(dev.off())

pdf(file.path(figureFolder, "gradient_SuHemiCorr.pdf"), width=10.5, height=7.5)
print(p2)
invisible(dev.off())

# Clear plots
remove(p1, p2)

## Sun inclination angle
## Solar inclination angle (height at midday)
# http://www.geoastro.de/astro/mittag/index.htm; h = 90° - β + δ
# Substract ghradient northern hemisphere and add to the southern
# 21.6 - "Summer"; +23.5°
h.w <- (90-abs(lat + 23.5)+latGrad.w)
h.s <- (90-abs(lat - 23.5)+latGrad.s)

# Plot
p1 <- levelplot(h.w,
                main = "Inclination angle sun, winter",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(h.w)), maxValue(abs(h.w)), len=100)) + 
  layer(sp.polygons(oceans, fill='blue', alpha=0.1))
print(p1)

p2 <- levelplot(h.s,
                main = "Inclination angle sun, summer",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(h.w)), maxValue(abs(h.w)), len=100)) + 
  layer(sp.polygons(oceans, fill='blue', alpha=0.1))
print(p2)

# Save plots
pdf(file.path(figureFolder, "inclination_winter.pdf"), width=10.5, height=7.5)
print(p1)
invisible(dev.off())

pdf(file.path(figureFolder, "inclination_summer.pdf"), width=10.5, height=7.5)
print(p2)
invisible(dev.off())

## Atmospheric distance
# Create distance layer
lat.w.rad <- abs(lat + 23.5)*pi/180
atmo.dist.w <- 1-cos(lat.w.rad)

lat.s.rad <- abs(lat - 23.5)*pi/180
atmo.dist.s <- 1-cos(lat.s.rad)

# Plot
p1 <- levelplot(atmo.dist.w,
                main = "Atmospheric distance, winter",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=T, 
                at=seq(-maxValue(abs(atmo.dist.w)), maxValue(abs(atmo.dist.w)), len=100)) + 
  layer(sp.polygons(oceans, fill='blue', alpha=0.1))
suppressWarnings(print(p1))

p2 <- levelplot(atmo.dist.s,
                main = "Atmospheric distance, summer",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=T, 
                at=seq(-maxValue(abs(atmo.dist.s)), maxValue(abs(atmo.dist.s)), len=100)) + 
  layer(sp.polygons(oceans, fill='blue', alpha=0.1))
suppressWarnings(print(p2))

# Save plots
pdf(file.path(figureFolder, "atmoDist_winter.pdf"), width=10.5, height=7.5)
suppressWarnings(print(p1))
invisible(dev.off())

pdf(file.path(figureFolder, "atmoDist_summer.pdf"), width=10.5, height=7.5)
suppressWarnings(print(p2))
invisible(dev.off())

remove(p1, p2)

## Interpolation
# Set up grid, for prediction
remove(grid)
#grid <- rasterToPoints(aggregate(landDEM, fact=30))
grid <- rasterToPoints(landDEM)
grid <- grid[,1:2]
grid <- SpatialPointsDataFrame(grid,data.frame(elev=extract(landDEM,grid)))
grid$cont <- extract(ocean.dist, grid)
grid$hsun <- extract(h.w, grid)
grid$dist <- extract(atmo.dist.w, grid)

# Define RMSE function
RMSE <- function(x,y){
  tmp <- (x-y)^2
  sqrt(mean(tmp))
}

### Winter before 1970
# Extract continentality and elevation at measurement points from rasters
temp1970w$elev <- extract(landDEM, temp1970w)
temp1970w$elev[is.na(temp1970w$elev)] <- 0
temp1970w$cont <- extract(ocean.dist, temp1970w)
temp1970w$cont[is.na(temp1970w$cont)] <- 0
temp1970w$hsun <- extract(h.w, temp1970w)
temp1970w$hsun[is.na(temp1970w$hsun)] <- 0
temp1970w$dist <- extract(atmo.dist.w, temp1970w)
temp1970w$dist[is.na(temp1970w$dist)] <- 0

# Linear Regression
temp1970w.lm.test <- lm(meansum~elev+cont+hsun+dist, data=temp1970w@data)
summary(temp1970w.lm.test)

# Distribution of residuals
temp1970w@data[names(temp1970w.lm.test$residuals),"lmRes"]<-temp1970w.lm.test$residuals
temp1970w@data$lmRes[is.na(temp1970w@data$lmRes)] <- 0
temp1970w$lmResRel<-temp1970w$lmRes/temp1970w$meansum

# Plot results
bubble(temp1970w,"lmRes",main="Residual Values", na.rm=T)
bubble(temp1970w,"lmResRel",main="Relative Residual Values", na.rm=T)
# plot(variogram(lmRes~1,temp1970w,width=10,cutoff=200),main="Residual Variogram")

# Compute distance matrix
temp1970w.d <- as.matrix(dist(cbind(temp1970w@coords[,1], temp1970w@coords[,2])), method = "euclidean", alternative = "greater")

# Inverse distance matrix
temp1970w.d.inv <- 1 / temp1970w.d

# Setting diagonal to 0
diag(temp1970w.d.inv) <- 0

# Print Moran's I
temp.moran <- Moran.I(temp1970w$lmRes, temp1970w.d.inv)
paste("Observed autocorrelation: ",temp.moran$observed)
paste("P-value of H0 (residuals are randomly distributed): ",temp.moran$p.value)

# Universal Kriging
temp1970w.best.m.index <- 3 # Gaussian model
temp1970w.uok <- krige(meansum~elev+cont+hsun+dist,
                       temp1970w, grid,
                       model = temp1970w.var10.fits[[temp1970w.best.m.index]])

# Create grid
gridded(temp1970w.uok)<-TRUE
temp1970w.uok.pred<-raster(temp1970w.uok, layer=1, values=TRUE)
temp1970w.uok.var<-raster(temp1970w.uok, layer=2, values=TRUE)

# Extract and append to test data
# "meanWi_before1970" "meanSu_before1970" "meanWi_after1990"  "meanSu_after1990"
temp.test$meanWi_before1970 <- extract(temp1970w.uok.pred, temp.test)

# Calculate RMSE of map
temp.val$meanWi_before1970_pred <- extract(temp1970w.uok.pred, temp.val)
paste("Observed RMSE (5% validation data): ", round(RMSE(temp.val$meanWi_before1970, temp.val$meanWi_before1970_pred),2),"°C", sep="")

# Plot
p1 <- levelplot(temp1970w.uok.pred,
                main = "Prediction: Winter before 1970",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(temp1970w.uok.pred)), maxValue(abs(temp1970w.uok.pred)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p1)

p2 <- levelplot(temp1970w.uok.var,
                main = "Uncertainty: Winter before 1970",
                maxpixels = maxpixels,
                par.settings=YlOrRdTheme(), margin=F, 
                at=seq(0, maxValue(abs(temp1970w.uok.var)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p2)

# Save plots
pdf(file.path(figureFolder, "temp1970w_pred.pdf"), width=10.5, height=7.5)
print(p1)
invisible(dev.off())

pdf(file.path(figureFolder, "temp1970w_var.pdf"), width=10.5, height=7.5)
print(p2)
invisible(dev.off())

# Clear plots
remove(p1, p2)

# Save raster
writeRaster(temp1970w.uok.pred, file.path(resultsFolder, "temp1970w_pred"), format = "GTiff", overwrite=TRUE)
writeRaster(temp1970w.uok.var, file.path(resultsFolder, "temp1970w_var"), format = "GTiff", overwrite=TRUE)

### Winter after 1990
# Extract continentality and elevation at measurement points from rasters
temp2010w$elev <- extract(landDEM, temp2010w)
temp2010w$elev[is.na(temp2010w$elev)] <- 0
temp2010w$cont <- extract(ocean.dist, temp2010w)
temp2010w$cont[is.na(temp2010w$cont)] <- 0
temp2010w$hsun <- extract(h.w, temp2010w)
temp2010w$hsun[is.na(temp2010w$hsun)] <- 0
temp2010w$dist <- extract(atmo.dist.w, temp2010w)
temp2010w$dist[is.na(temp2010w$dist)] <- 0

# Linear Regression
temp2010w.lm.test <- lm(meansum~elev+cont+hsun+dist, data=temp2010w@data)
summary(temp2010w.lm.test)

# Distribution of residuals
temp2010w@data[names(temp2010w.lm.test$residuals),"lmRes"]<-temp2010w.lm.test$residuals
temp2010w@data$lmRes[is.na(temp2010w@data$lmRes)] <- 0
temp2010w$lmResRel<-temp2010w$lmRes/temp2010w$meansum

# Remove outlier
temp2010w$lmResRel[which.max(temp2010w$lmResRel)] <- mean(temp2010w$lmResRel)
temp2010w$lmResRel[which.max(temp2010w$lmResRel)] <- mean(temp2010w$lmResRel)
temp2010w$lmResRel[which.max(temp2010w$lmResRel)] <- mean(temp2010w$lmResRel)
temp2010w$lmResRel[which.max(temp2010w$lmResRel)] <- mean(temp2010w$lmResRel)
temp2010w$lmResRel[which.max(temp2010w$lmResRel)] <- mean(temp2010w$lmResRel)

# Plot results
bubble(temp2010w,"lmRes",main="Residual Values", na.rm=T)
bubble(temp2010w,"lmResRel",main="Relative Residual Values", na.rm=T)

# Compute distance matrix
temp2010w.d <- as.matrix(dist(cbind(temp2010w@coords[,1], temp2010w@coords[,2])), method = "euclidean", alternative = "greater")

# Inverse distance matrix
temp2010w.d.inv <- 1 / temp2010w.d

# Setting diagonal to 0
diag(temp2010w.d.inv) <- 0

# Print Moran's I
temp.moran <- Moran.I(temp2010w$lmRes, temp2010w.d.inv)
paste("Observed autocorrelation: ",temp.moran$observed)
paste("P-value of H0 (residuals are randomly distributed): ",temp.moran$p.value)

# Universal Kriging
temp2010w.best.m.index <- 3 # Gaussian model
temp2010w.uok <- krige(meansum~elev+cont+hsun+dist,
                       temp2010w, grid,
                       model = temp2010w.var10.fits[[temp2010w.best.m.index]])

# Create grid
gridded(temp2010w.uok)<-TRUE
temp2010w.uok.pred<-raster(temp2010w.uok, layer=1, values=TRUE)
temp2010w.uok.var<-raster(temp2010w.uok, layer=2, values=TRUE)

# Extract and append to test data
# "meanWi_before1970" "meanSu_before1970" "meanWi_after1990"  "meanSu_after1990"
temp.test$meanWi_after1990 <- extract(temp2010w.uok.pred, temp.test)

# Calculate RMSE of map
temp.val$meanWi_after1990_pred <- extract(temp2010w.uok.pred, temp.val)
paste("Observed RMSE (5% validation data): ", round(RMSE(temp.val$meanWi_after1990, temp.val$meanWi_after1990_pred),2),"°C", sep="")

# Plot
p1 <- levelplot(temp2010w.uok.pred,
                main = "Prediction: Winter after 1990",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(temp2010w.uok.pred)), maxValue(abs(temp2010w.uok.pred)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p1)

p2 <- levelplot(temp2010w.uok.var,
                main = "Uncertainty: Winter after 1990",
                maxpixels = maxpixels,
                par.settings=YlOrRdTheme(), margin=F, 
                at=seq(0, maxValue(abs(temp2010w.uok.var)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p2)

# Save plots
pdf(file.path(figureFolder, "temp2010w_pred.pdf"), width=10.5, height=7.5)
print(p1)
invisible(dev.off())

pdf(file.path(figureFolder, "temp2010w_var.pdf"), width=10.5, height=7.5)
print(p2)
invisible(dev.off())

# Clear plots
remove(p1, p2)

# Save raster
writeRaster(temp2010w.uok.pred, file.path(resultsFolder, "temp2010w_pred"), format = "GTiff", overwrite=TRUE)
writeRaster(temp2010w.uok.var, file.path(resultsFolder, "temp2010w_var"), format = "GTiff", overwrite=TRUE)

### Summer before 1970
# !!! Adjust grid for summer
grid$hsun <- extract(h.s, grid)
grid$dist <- extract(atmo.dist.s, grid)

# Extract continentality and elevation at measurement points from rasters
temp1970s$elev <- extract(landDEM, temp1970s)
temp1970s$elev[is.na(temp1970s$elev)] <- 0
temp1970s$cont <- extract(ocean.dist, temp1970s)
temp1970s$cont[is.na(temp1970s$cont)] <- 0
temp1970s$hsun <- extract(h.s, temp1970s)
temp1970s$hsun[is.na(temp1970s$hsun)] <- 0
temp1970s$dist <- extract(atmo.dist.s, temp1970s)
temp1970s$dist[is.na(temp1970s$dist)] <- 0

# Linear Regression
temp1970s.lm.test <- lm(meansum~elev+cont+hsun+dist, data=temp1970s@data)
summary(temp1970s.lm.test)

# Distribution of residuals
temp1970s@data[names(temp1970s.lm.test$residuals),"lmRes"]<-temp1970s.lm.test$residuals
temp1970s@data$lmRes[is.na(temp1970s@data$lmRes)] <- 0
temp1970s$lmResRel<-temp1970s$lmRes/temp1970s$meansum

# Plot results
bubble(temp1970s,"lmRes",main="Residual Values", na.rm=T)
bubble(temp1970s,"lmResRel",main="Relative Residual Values", na.rm=T)
# plot(variogram(lmRes~1,temp1970s,width=10,cutoff=200),main="Residual Variogram")

# Compute distance matrix
temp1970s.d <- as.matrix(dist(cbind(temp1970s@coords[,1], temp1970s@coords[,2])), method = "euclidean", alternative = "greater")

# Inverse distance matrix
temp1970s.d.inv <- 1 / temp1970s.d

# Setting diagonal to 0
diag(temp1970s.d.inv) <- 0

# Print Moran's I
temp.moran <- Moran.I(temp1970s$lmRes, temp1970s.d.inv)
paste("Observed autocorrelation: ",temp.moran$observed)
paste("P-value of H0 (residuals are randomly distributed): ",temp.moran$p.value)

# Universal Kriging
temp1970s.best.m.index <- 3 # Gaussian model
temp1970s.uok <- krige(meansum~elev+cont+hsun+dist,
                       temp1970s, grid,
                       model = temp1970s.var10.fits[[temp1970s.best.m.index]])

# Create grid
gridded(temp1970s.uok)<-TRUE
temp1970s.uok.pred<-raster(temp1970s.uok, layer=1, values=TRUE)
temp1970s.uok.var<-raster(temp1970s.uok, layer=2, values=TRUE)

# Extract and append to test data
# "meanWi_before1970" "meanSu_before1970" "meanWi_after1990"  "meanSu_after1990"
temp.test$meanSu_before1970 <- extract(temp1970s.uok.pred, temp.test)

# Calculate RMSE of map
temp.val$meanSu_before1970_pred <- extract(temp1970s.uok.pred, temp.val)
paste("Observed RMSE (5% validation data): ", round(RMSE(temp.val$meanSu_before1970, temp.val$meanSu_before1970_pred),2),"°C", sep="")

# Plot
p1 <- levelplot(temp1970s.uok.pred,
                main = "Prediction: Summer before 1970",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(temp1970s.uok.pred)), maxValue(abs(temp1970s.uok.pred)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p1)

p2 <- levelplot(temp1970s.uok.var,
                main = "Uncertainty: Summer before 1970",
                maxpixels = maxpixels,
                par.settings=YlOrRdTheme(), margin=F, 
                at=seq(0, maxValue(abs(temp1970s.uok.var)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p2)

# Save plots
pdf(file.path(figureFolder, "temp1970s_pred.pdf"), width=10.5, height=7.5)
print(p1)
invisible(dev.off())

pdf(file.path(figureFolder, "temp1970s_var.pdf"), width=10.5, height=7.5)
print(p2)
invisible(dev.off())

# Clear plots
remove(p1, p2)

# Save raster
writeRaster(temp1970s.uok.pred, file.path(resultsFolder, "temp1970s_pred"), format = "GTiff", overwrite=TRUE)
writeRaster(temp1970s.uok.var, file.path(resultsFolder, "temp1970s_var"), format = "GTiff", overwrite=TRUE)

### Summer after 1990
# Extract continentality and elevation at measurement points from rasters
temp2010s$elev <- extract(landDEM, temp2010s)
temp2010s$elev[is.na(temp2010s$elev)] <- 0
temp2010s$cont <- extract(ocean.dist, temp2010s)
temp2010s$cont[is.na(temp2010s$cont)] <- 0
temp2010s$hsun <- extract(h.s, temp2010s)
temp2010s$hsun[is.na(temp2010s$hsun)] <- 0
temp2010s$dist <- extract(atmo.dist.s, temp2010s)
temp2010s$dist[is.na(temp2010s$dist)] <- 0

# Linear Regression
temp2010s.lm.test <- lm(meansum~elev+cont+hsun+dist, data=temp2010s@data)
summary(temp2010s.lm.test)

# Distribution of residuals
temp2010s@data[names(temp2010s.lm.test$residuals),"lmRes"]<-temp2010s.lm.test$residuals
temp2010s@data$lmRes[is.na(temp2010s@data$lmRes)] <- 0
temp2010s$lmResRel<-temp2010s$lmRes/temp2010s$meansum

# Plot results
bubble(temp2010s,"lmRes",main="Residual Values", na.rm=T)
bubble(temp2010s,"lmResRel",main="Relative Residual Values", na.rm=T)
# plot(variogram(lmRes~1,temp2010s,width=10,cutoff=200),main="Residual Variogram")

# Compute distance matrix
temp2010s.d <- as.matrix(dist(cbind(temp2010s@coords[,1], temp2010s@coords[,2])), method = "euclidean", alternative = "greater")

# Inverse distance matrix
temp2010s.d.inv <- 1 / temp2010s.d

# Setting diagonal to 0
diag(temp2010s.d.inv) <- 0

# Print Moran's I
temp.moran <- Moran.I(temp2010s$lmRes, temp2010s.d.inv)
paste("Observed autocorrelation: ",temp.moran$observed)
paste("P-value of H0 (residuals are randomly distributed): ",temp.moran$p.value)

# Universal Kriging
temp2010s.best.m.index <- 3 # Gaussian model
temp2010s.uok <- krige(meansum~elev+cont+hsun+dist,
                       temp2010s, grid,
                       model = temp2010s.var10.fits[[temp2010s.best.m.index]])

# Create grid
gridded(temp2010s.uok)<-TRUE
temp2010s.uok.pred<-raster(temp2010s.uok, layer=1, values=TRUE)
temp2010s.uok.var<-raster(temp2010s.uok, layer=2, values=TRUE)

# Extract and append to test data
# "meanWi_before1970" "meanSu_before1970" "meanWi_after1990"  "meanSu_after1990"
temp.test$meanSu_after1990 <- extract(temp2010s.uok.pred, temp.test)

# Calculate RMSE of map
temp.val$meanSu_after1990_pred <- extract(temp2010s.uok.pred, temp.val)
paste("Observed RMSE (5% validation data): ", round(RMSE(temp.val$meanSu_after1990, temp.val$meanSu_after1990_pred),2),"°C", sep="")

# Plot
p1 <- levelplot(temp2010s.uok.pred,
                main = "Prediction: Summer after 1990",
                maxpixels = maxpixels,
                par.settings=BuRdTheme(), margin=F, 
                at=seq(-maxValue(abs(temp2010s.uok.pred)), maxValue(abs(temp2010s.uok.pred)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p1)

p2 <- levelplot(temp2010s.uok.var,
                main = "Uncertainty: Summer after 1990",
                maxpixels = maxpixels,
                par.settings=YlOrRdTheme(), margin=F, 
                at=seq(0, maxValue(abs(temp2010s.uok.var)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p2)

# Save plots
pdf(file.path(figureFolder, "temp2010s_pred.pdf"), width=10.5, height=7.5)
print(p1)
invisible(dev.off())

pdf(file.path(figureFolder, "temp2010s_var.pdf"), width=10.5, height=7.5)
print(p2)
invisible(dev.off())

# Clear plots
remove(p1, p2)

# Save raster
writeRaster(temp2010s.uok.pred, file.path(resultsFolder, "temp2010s_pred"), format = "GTiff", overwrite=TRUE)
writeRaster(temp2010s.uok.var, file.path(resultsFolder, "temp2010s_var"), format = "GTiff", overwrite=TRUE)

# Save temperature_test_pred.csv
write.csv(temp.test, file = file.path(resultsFolder, "temperature_test_pred"), row.names = FALSE)

# Difference images
## Winter
diff.w <- temp2010w.uok.pred-temp1970w.uok.pred

# Plot
p <- levelplot(diff.w,
               main = "Temperature change: Winter",
               maxpixels = maxpixels,
               par.settings=BuRdTheme(), margin=F, 
               at=seq(-maxValue(abs(diff.w)), maxValue(abs(diff.w)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p)

# Save plots
pdf(file.path(figureFolder, "diff_winter.pdf"), width=10.5, height=7.5)
print(p)
invisible(dev.off())

# Clear plots
remove(p)

# Save raster
writeRaster(diff.w, file.path(resultsFolder, "diff_winter"), format = "GTiff", overwrite=TRUE)

## Summer
diff.s <- temp2010s.uok.pred-temp1970s.uok.pred

# Plot
p <- levelplot(diff.s,
               main = "Temperature change: Summer",
               maxpixels = maxpixels,
               par.settings=BuRdTheme(), margin=F, 
               at=seq(-maxValue(abs(diff.s)), maxValue(abs(diff.s)), len=100)) + 
  layer(sp.polygons(oceans, fill='transparent'))
print(p)

# Save plots
pdf(file.path(figureFolder, "diff_summer.pdf"), width=10.5, height=7.5)
print(p)
invisible(dev.off())

# Clear plots
remove(p)

# Save raster
writeRaster(diff.s, file.path(resultsFolder, "diff_summer"), format = "GTiff", overwrite=TRUE)
