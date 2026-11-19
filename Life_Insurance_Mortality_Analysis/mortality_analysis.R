# ==============================================================================
# Life Insurance Mortality Analysis (USA, 1950-1990)
# Author: Devansh Mittal
# Purpose: Build period life tables from Human Mortality Database data,
#          compare sexes and years, and fit a Gompertz mortality model.
# Data: Human Mortality Database (www.mortality.org), USA, period 1x1 files:
#       Deaths_1x1.txt and Exposures_1x1.txt (stored in /data)
# ==============================================================================

# install.packages(c("readr","dplyr"))

# Load required libraries
library(dplyr)          # data manipulation and the %>% pipe
library(readr)          # parse_number()
options(scipen=999)     # show 100000 instead of 1e+05 on axes and in CSV files

# Create the plots folder if it does not already exist
dir.create("plots",showWarnings=FALSE,recursive=TRUE)
dir.create("outputs",showWarnings=FALSE,recursive=TRUE)

# Import annual death and exposure datasets
deaths<-read.table("data/Deaths_1x1.txt",header=TRUE,sep="",skip=2,
                   na.strings=c(".",""))

exposures<-read.table("data/Exposures_1x1.txt",header=TRUE,sep="",skip=2,
                        na.strings=c(".",""))
head(deaths);head(exposures)
range(deaths$Year);range(exposures$Year)

# Builds a period life table for one calendar year and sex.
build_life_table<-function(year,sex="Total",max_age=100,radix=100000){
  deaths_selected<-deaths%>%
    filter(Year==year)%>%
    transmute(Age=readr::parse_number(as.character(Age)),Deaths=.data[[sex]])
  
  exposures_selected<-exposures%>%
    filter(Year==year)%>%
    transmute(Age=readr::parse_number(as.character(Age)),Exposure=.data[[sex]])
  
  data<-inner_join(deaths_selected,exposures_selected,by="Age")%>%
    filter(Age<=max_age,!is.na(Deaths),!is.na(Exposure),Exposure>0)%>%
    arrange(Age)
  
  if(nrow(data)==0||!all(diff(data$Age)==1)){
    stop("Missing or non-consecutive ages. Check the selected data.")
  }
  n<-nrow(data)
  data<-data%>%
    mutate(Year=year,
           mx=Deaths/Exposure,            # central mortality rate
           ax=ifelse(Age==0,0.1,0.5),     # average fraction of the year lived by those who die  (0.1 for infants, 0.5 otherwise)
           qx=mx/(1+(1-ax)*mx))           # probability of dying within the year
  
  data$qx[n]<-1                           # close the table: everyone dies in the last age group
  data$px<-1-data$qx
  
  lx<-radix*c(1,cumprod(data$px[-n]))     # survivors at exact age x
  dx<-lx*data$qx                          # deaths between x and x+1
  Lx<-lx-(1-data$ax) * dx                 # person-years lived in the interval
  Lx[n]<-lx[n]/data$mx[n]                 # final (open) interval
  Tx<-rev(cumsum(rev(Lx)))                # total future person-years
  ex<-Tx/lx                               # remaining life expectancy
  
  data%>%mutate(lx=lx,dx=dx,Lx=Lx,Tx=Tx,ex=ex)
}

# ---- 1950 total-population life table ----
chosen_year<-1950
life_table_1950<-build_life_table(year=chosen_year,sex="Total")
head(life_table_1950);tail(life_table_1950)
summary(life_table_1950)

write.csv(life_table_1950,"outputs/Life_Table_1950.csv",row.names=FALSE)


# Helper: draw a plot on screen (RStudio Plots pane), then draw the same plot into a PNG file
show_and_save<-function(file,draw_fun){
  if(interactive()) draw_fun()       # show in the Plots pane (skipped under Rscript)
  png(file,width=8,height=6,units="in",res=300)
  draw_fun()                         # same drawing into the file
  invisible(dev.off())               # close and write the PNG
}

# Helper: single line chart of one life-table column against age
save_line_plot <- function(x,y,file,main,xlab,ylab,col,logy=FALSE){
  show_and_save(file,function(){
    plot(x, y,type="l",col=col,lwd=2,log=if (logy) "y" else "",main=main,
         xlab=xlab,ylab=ylab)
    grid()
  })
}

# qx at the last age is set to 1 only to close the table (not real data),
# so qx is plotted up to age 99
ages_lt<-life_table_1950$Age
ok<-ages_lt<100

save_line_plot(ages_lt,life_table_1950$mx,"plots/Mortality_Rate.png",
               "Mortality Rate by Age (USA,1950)","Age",
               "Central Mortality Rate (mx,log scale)","blue",logy=TRUE)

save_line_plot(ages_lt[ok],life_table_1950$qx[ok],"plots/Probability_of_Death.png",
               "Probability of Death by Age (USA,1950)","Age",
               "Probability of Death (qx,log scale)","red",logy=TRUE)

save_line_plot(ages_lt, life_table_1950$lx,"plots/Survival_Curve.png",
               "Life Table Survival Curve (USA,1950)","Age",
               "Number of Survivors (out of 100,000 births)","darkgreen")

save_line_plot(ages_lt, life_table_1950$ex,"plots/Life_Expectancy.png",
               "Life Expectancy by Age (USA,1950)","Age",
               "Remaining Life Expectancy (Years)","purple")

# Validation checks: the script stops with an error if any check fails
ages_check<-life_table_1950$Age%in%1:90
stopifnot(
all(life_table_1950$mx>=0),
all(life_table_1950$qx>=0&life_table_1950$qx<=1),
all(life_table_1950$px>=0&life_table_1950$px<=1),
all(diff(life_table_1950$lx)<=0),                  # survivors never increase
isTRUE(all.equal(sum(life_table_1950$dx),100000)), # table closes: all 100,000 lives end
all(is.finite(life_table_1950$ex)),
# Life expectancy should fall with age from age 1 to 90.
# (It rises at age 0-1 because of infant mortality, and is noisy above ~95 because very few people are observed at those ages.)
all(diff(life_table_1950$ex[ages_check])<0)
);print("All life table validation checks passed.")


# Male & Female life table
male_1950<-build_life_table(year=1950,sex="Male")
female_1950<-build_life_table(year=1950,sex="Female")

# Helper: male vs female line chart of one life-table column (uses male_1950 and female_1950)
sex_plot<-function(var,file,main,ylab,logy=FALSE,pos="topleft",max_age=100){
  f<-female_1950[female_1950$Age<=max_age,]
  m<-male_1950[male_1950$Age<=max_age,]
  show_and_save(file,function(){
    plot(f$Age,f[[var]],type="l",col="red",lwd=2,log=if (logy) "y" else "",
         ylim=range(c(m[[var]],f[[var]])),main=main,xlab="Age",ylab=ylab)
    lines(m$Age,m[[var]],col="blue",lwd=2)
    grid()
    legend(pos,legend=c("Female","Male"),col=c("red","blue"),lwd=2,bty="n")
  })
}

# Male vs female charts: mortality rate and life expectancy
sex_plot("mx","plots/Male_Female_Mortality.png",
         "Male vs Female Mortality Rates(USA,1950)",
         "Central Mortality Rate(mx,log scale)",logy=TRUE)

sex_plot("ex","plots/Male_Female_Life_Expectancy.png",
         "Male vs Female Life Expectancy(USA,1950)",
         "Remaining Life Expectancy(Years)",pos="topright")


# Male vs female comparison (1950) 
sex_data<-bind_rows(male_1950%>%
                      mutate(Sex="Male"),
                    female_1950%>%
                      mutate(Sex="Female"))

sex_comparison<-sex_data%>%
  filter(Age%in%c(0,20,40,60,70))%>%
  select(Sex,Age,lx,qx,ex)%>%
  arrange(Age,Sex)
print(sex_comparison)

# Female advantage in life expectancy at birth(years)
(difference_e0<-female_1950$ex[female_1950$Age==0]-
    male_1950$ex[male_1950$Age==0])
# Women outlived men by about 5.6 years in 1950

write.csv(sex_comparison,"outputs/Male_Female_Comparison.csv",row.names=FALSE)

# Probability of death(log scale shows the exponential rise with age)
sex_plot("qx","plots/Male_Female_Qx.png",
         "Male vs Female Probability of Death (USA,1950)",
         "Probability of Death (qx,log scale)",logy=TRUE,max_age=99)

# Survival curves: how many of 100,000 newborns are still alive at each age
sex_plot("lx","plots/Male_Female_Survival.png",
         "Male vs Female Survival Curves(USA,1950)",
         "Number of Survivors",pos="bottomleft")

# Historical comparison
life_1950<-build_life_table(year=1950,sex="Total")
life_1970<-build_life_table(year=1970,sex="Total")
life_1990<-build_life_table(year=1990,sex="Total")

historical_data<-bind_rows(life_1950,life_1970,life_1990)   

common_ages<-c(0,20,40,60,70)

historical_summary<-historical_data%>%
  filter(Age%in%common_ages)%>%
  select(Year,Age,lx,qx,ex)%>%
  arrange(Age,Year)
print(historical_summary)

historical_comparison<-historical_data%>%
  filter(Age%in%common_ages)%>%
  select(Year,Age,mx,qx)%>%
  arrange(Age,Year)
print(historical_comparison)
# Mortality fell between 1950 and 1990 at every age shown, most strongly in infancy
# (age 20 was flat between 1950 and 1970 before falling)

# Helper: one line per age across 1950, 1970 and 1990
hist_plot<-function(var,file,main,ylab){
  ages<-sort(unique(historical_comparison$Age))
  cols<-hcl.colors(length(ages),"Dark 3")
  
  show_and_save(file,function(){
    op<-par(mar=c(5,4,4,6));on.exit(par(op))
    plot(NA,xlim=range(historical_comparison$Year),
         ylim=range(historical_comparison[[var]]),log="y",xaxt="n",main=main,
         xlab="Year",ylab=ylab)
    axis(1,at=sort(unique(historical_comparison$Year)))
    grid()
    for(i in seq_along(ages)){
      d<-historical_comparison[historical_comparison$Age==ages[i],]
      lines(d$Year,d[[var]],type="b",pch=19,col=cols[i],lwd=2)
    }
    legend("topright",inset=c(-0.15,0),xpd=TRUE,title="Age",legend=ages,
           col=cols,lwd=2,pch=19,bty="n")
  })
}

hist_plot("mx","plots/Historical_Mortality_Rate.png",
          "Historical Mortality Rates (USA,1950,1970,1990)",
          "Central Mortality Rate (mx,log scale)")
hist_plot("qx","plots/Historical_Qx.png",
          "Historical Probability of Death (USA,1950,1970,1990)",
          "Probability of Death (qx,log scale)")

write.csv(historical_comparison,"outputs/Historical_Mortality_Comparison.csv",
          row.names=FALSE)

# Gompertz model(mx=B*c^x)
# Mortality in adult life grows roughly exponentially with age. Taking logs
# turns this into a straight line(log(mx)=log(B)+x*log(c))
# so it can be fitted with ordinary linear regression.
# Ages 30-90 are used:below 30 accidents dominate & above 90 the data are sparse.

gompertz_data<-life_1950%>%
  filter(Age>=30,Age<=90,mx>0)%>%
  mutate(log_mx=log(mx))

gompertz_model<-lm(log_mx~Age,data=gompertz_data)
summary(gompertz_model)

alpha<-unname(coef(gompertz_model)[1])           # intercept
beta<-unname(coef(gompertz_model)[2])            # slope

(B<-exp(alpha))                    # baseline mortality at age 0 (extrapolated)
(gomp_c<-exp(beta))                # yearly growth factor of mortality
(doubling_time<-log(2)/beta)       # years for mortality to double
# Adult mortality doubles roughly every 8.4 years of age.
# This relationship helps explain why mortality risk increases
# substantially with age and is relevant to life insurance analysis.

# Fitted values on the original (non-log) scale
gompertz_data$fitted_mx<-exp(predict(gompertz_model))


show_and_save("plots/Gompertz_Model.png",function(){
  plot(gompertz_data$Age,gompertz_data$mx,log="y",
       pch=19,col=adjustcolor("black",alpha.f=0.6),
       main="Gompertz Model: Actual vs Fitted Mortality (USA, 1950, ages 30-90)",
       xlab="Age",ylab="Mortality Rate (log scale)")
  lines(gompertz_data$Age,gompertz_data$fitted_mx,lwd=2,col="red")
  grid()
  legend("topleft",legend=c("Actual","Fitted"),pch=c(19,NA),lty=c(NA,1),
         lwd=c(NA, 2),col=c("black","red"),bty="n")
})

gompertz_summary<-data.frame(
  Parameter=c("B","c","Doubling Time(years)","R-squared"),
  Value=c(B,gomp_c,doubling_time,summary(gompertz_model)$r.squared))
print(gompertz_summary)

write.csv(gompertz_summary,"outputs/Gompertz_Model_Results.csv",row.names=FALSE)


# Verify the number of generated plots and output tables
cat("Number of plots generated:",
    length(list.files("plots",pattern="\\.png$")),
    "\n");print(list.files("plots",pattern="\\.png$"))   # should list 11 plots

cat("Number of CSV files generated:",
    length(list.files("outputs",pattern="\\.csv$")),
    "\n");print(list.files("outputs",pattern="\\.csv$"))  # should list 4 CSV files

# ==============================================================================
# SUMMARY OF FINDINGS (USA, Human Mortality Database)
# ------------------------------------------------------------------------------
# 1. Life expectancy at birth rose from 68.1 years (1950) to 70.7 (1970)
#    and 75.4 (1990).
# 2. In 1950, women outlived men by about 5.6 years at birth
#    (71.0 vs 65.4 years), and the gap narrowed at older ages.
# 3. Mortality declined between 1950 and 1990 at every age shown,with the 
#    largest proportional decline occurring in infancy.At age 20, mortality
#    increased slightly between 1950 and 1970 before declining by 1990.
# 4. Adult mortality (ages 30-90) follows a Gompertz curve very closely
#    (R-squared = 0.9996): it grows about 8.6% per year of age (c = 1.086)
#    and doubles roughly every 8.4 years. This demonstrates the usefulness
#    of the Gompertz model in describing age-related mortality patterns.

# LIMITATIONS
# - Uses the standard approximation ax = 0.5 (0.1 for infants).
# - Data above age 90 are sparse, so results there are noisy.
# - Only three years (1950, 1970, 1990) are compared.
# - The Gompertz model is fitted by unweighted regression on the log scale.
#
# OUTPUTS: 11 charts in plots/ and 4 tables in outputs/.
# ==============================================================================