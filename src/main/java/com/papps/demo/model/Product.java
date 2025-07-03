package com.papps.demo.model;

import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.Setter;
import lombok.ToString;

@Setter
@Getter
@ToString //@Data
@AllArgsConstructor
public class Product {

	private Integer id;
    private String name;
    private Long price;
    
    public Product() {
    	
    }
	public Product(Integer id, String name, Long price) {
		super();
		this.id = id;
		this.name = name;
		this.price = price;
	}
	public Integer getId() {
		return id;
	}
	public void setId(Integer id) {
		this.id = id;
	}
	public String getName() {
		return name;
	}
	public void setName(String name) {
		this.name = name;
	}
	public Long getPrice() {
		return price;
	}
	public void setPrice(Long price) {
		this.price = price;
	}
	@Override
	public String toString() {
		return "Product [id=" + id + ", name=" + name + ", price=" + price + ", getId()=" + getId() + ", getName()="
				+ getName() + ", getPrice()=" + getPrice() + "]";
	}
	
	
    
    
}
