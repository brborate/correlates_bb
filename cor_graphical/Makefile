## all            : clear current results and make figures
all: clean figs

## clean_data     : saves data sets for plotting in data_clean
clean_data: code/data_prep.R
	Rscript code/data_prep.R

## figs           : make figures
figs: fig_code clean_data
	Rscript code/cor_graphics_violin_scatter.R
fig_code: code/cor_graphics_violin_scatter.R

## clean          : clean up data_clean and output folder
clean: 
	rm -f data_clean/* && rm -f output/*

# type 'make help' to show all make commands
help: Makefile
	@sed -n 's/^##//p' $<

.PHONY: fig_code figs clean all clean_data