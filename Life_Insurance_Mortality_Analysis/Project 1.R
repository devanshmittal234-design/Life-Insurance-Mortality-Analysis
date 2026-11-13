install.packages(c("tidyverse","ggplot2","readr","dplyr"))

# Load required libraries for data manipulation,data cleaning, and data visualization
library(tidyverse)
library(ggplot2)
library(readr)
library(dplyr)

# Import annual death and exposure datasets
deaths<-read.table("C:/Users/devan/Desktop/Life_Insurance_Mortality_Analysis/data/Deaths_1x1.txt",
                     header=TRUE,sep="",skip=2)
exposures<-read.table("C:/Users/devan/Desktop/Life_Insurance_Mortality_Analysis/data/cExposures_1x1.txt",
                      header=TRUE,sep="",skip=2)
head(deaths);head(exposures)
range(deaths$Year);range(exposures$Year)

# Select any year for mortality analysis that lies in range of both deaths & exposures
chosen_year<-1950

# Clean the death dataset by extracting numerical age values, filtering the selected year
deaths_clean<-deaths%>%
  mutate(Age=readr::parse_number(as.character(Age)))%>%
  filter(Year==chosen_year)%>%
  select(Age,Deaths=Total)
# Clean the exposure dataset using the same procedure and retain total exposure values
exposures_clean<-exposures%>%
  mutate(Age=readr::parse_number(as.character(Age)))%>%
  filter(Year==chosen_year) %>%
  select(Age,Exposure=Total)

head(deaths_clean);head(exposures_clean)

# Merge death and exposure datasets using age to create a combined mortality dataset
mortality_data<-inner_join(deaths_clean,exposures_clean,by="Age")%>%
  arrange(Age)

head(mortality_data)
summary(mortality_data)

# Calculate the central mortality rate (mx)
# Mortality rate=Total Deaths/Total Exposure
mortality_data<-mortality_data%>%
  mutate(Deaths=readr::parse_number(as.character(Deaths)),
         Exposure=readr::parse_number(as.character(Exposure)),
         )
mortality_data$mx<-ifelse(!is.na(mortality_data$Exposure)&mortality_data$Exposure>0,
                          mortality_data$Deaths/mortality_data$Exposure,NA)
head(mortality_data)


# Construct the life table using mortality data for ages 0 to 73
# Only observations with valid positive exposure and non-missing death counts are included
life_table_73<-mortality_data%>%
  filter(!is.na(Exposure),Exposure>0,!is.na(Deaths),Age<=73)%>%
  arrange(Age)%>%
  mutate(mx=Deaths/Exposure)


# Assuming that the deaths are uniformly distributed throughout each year of age (ax = 0.5)
# Calculate qx (the probability of dying between age x and age x+1)
ax<-0.5
qx<-life_table_73$mx/(1+(1-ax)*life_table_73$mx)
life_table_73<-cbind(life_table_73,ax,qx)
life_table_73$px<-1-life_table_73$qx

head(life_table_73);tail(life_table_73)

# Calculate the number of survivors (lx) and deaths (dx) using an initial population of 100,000 individuals
n<-nrow(life_table_73)
lx<-numeric(n)
lx[1]<-100000
for(i in 1:(n-1)){
  lx[i+1]<-lx[i]*(life_table_73$px[i])
}
dx<-lx*life_table_73$qx

# Calculate Lx, the number of person-years lived during each one-year age interval
Lx<-lx-(1-life_table_73$ax)*dx

life_table_73$lx<-lx
life_table_73$dx<-dx
life_table_73$Lx<-Lx

# Calculate Tx, the total future person-years remaining from each age onwards
Tx<-rev(cumsum(rev(life_table_73$Lx)))
life_table_73$Tx<-Tx

# Calculate ex, the expected remaining lifetime at each age using Tx divided by lx
ex<-Tx/lx
life_table_73$ex<-ex

head(life_table_73);tail(life_table_73)
summary(life_table_73)

ggplot(life_table_73,aes(x=Age,y=mx))+geom_line(color="blue",linewidth=1)+labs(
    title="Mortality Rate by Age",x="Age",y="Mortality Rate (mx)")+
  theme_minimal()

ggplot(life_table_73,aes(x=Age,y=qx))+geom_line(color="red",linewidth=1)+labs(
    title="Probability of Death by Age",x="Age",y="Probability of Death (qx)")+
  theme_minimal()

ggplot(life_table_73,aes(x=Age,y=lx))+geom_line(color="darkgreen",linewidth=1)+
  labs(title="Life Table Survival Curve",x="Age",y="Number of Survivors")+
  theme_minimal()

ggplot(life_table_73,aes(x=Age,y=ex))+geom_line(color="purple",linewidth=1)+
  labs(title="Life Expectancy by Age",x="Age",y="Remaining Life Expectancy (Years)")+
  theme_minimal()

# Identify and rank the ten ages with the highest central mortality rates
highest_mortality<-life_table_73%>%
  arrange(desc(mx))%>%
  select(Age,Deaths,Exposure,mx,qx)

head(highest_mortality,10)

# Extract life table indicators for selected ages to compare mortality and survival patterns
selected_ages<-life_table_73%>%
  filter(Age %in% c(0,20,40,60,70))%>%
  select(Age,lx,qx,ex)

selected_ages

write.csv(life_table_73,
  "C:/Users/devan/Desktop/Life_Insurance_Mortality_Analysis/Life_Table_1950.csv",
  row.names=FALSE)
write.csv(selected_ages,
          "C:/Users/devan/Desktop/Life_Insurance_Mortality_Analysis/Life_Expectancy_Summary.csv",
          row.names=FALSE)


# Project Conclusion
# The mortality analysis of the year 1950 reveals a U-shaped relationship between age and 
# mortality rates. Mortality is relatively high during infancy, decreases significantly 
# during childhood, and gradually increases with age.
# The life table constructed using an initial hypothetical population of 100,000 individuals
# demonstrates the decline in survivors as age increases.
# The analysis also highlights the relationship between mortality rates, probability of death,
# survival probability, and remaining life expectancy.

# Limitation
# The life table is restricted to ages 0–73 because of missing exposure data at older ages. 
# Therefore, the calculated life expectancy values should be interpreted as estimates based 
# on this restricted age range rather than complete life expectancy estimates.
